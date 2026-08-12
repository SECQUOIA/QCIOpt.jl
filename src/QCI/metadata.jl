@doc raw"""
    qci_response_field(value, path::AbstractString...)

Read a nested field out of a provider response, returning `nothing` when any
step of `path` is absent or the value at that step is not a dictionary.

Every field of a QCI job response other than `"status"` is optional as far as
this package is concerned: the provider fills `job_info`, `job_status`, and
`job_result` progressively, and a job that never ran carries none of them. So
derived metadata reads through this helper instead of indexing directly, which
is what keeps a missing provider field from turning into a `KeyError` inside an
unrelated `MOI.get` call.
"""
function qci_response_field(value, path::AbstractString...)
    current = value

    for key in path
        if current isa AbstractDict && haskey(current, key)
            current = current[key]
        else
            return nothing
        end
    end

    return current
end

@doc raw"""
    qci_parse_timestamp(value)

Parse one QCI job-status timestamp into a `DateTime`, or return `nothing` when
`value` is not a timestamp this package can compare.

The provider reports job-status timestamps under `rfc3339nano` keys, so the
fractional part can carry more precision than `DateTime` represents; it is
truncated to milliseconds. A timestamp carrying an explicit numeric UTC offset
is rejected rather than parsed as if it were UTC, because a duration taken
across two differently-offset timestamps would be wrong by whole hours without
any sign of it in the result.
"""
function qci_parse_timestamp(value)
    value isa AbstractString || return nothing

    m = match(
        r"^(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2})(?:\.(\d+))?[Zz]?$",
        strip(value),
    )

    isnothing(m) && return nothing

    millisecond = isnothing(m[3]) ? "000" : rpad(first(m[3], 3), 3, '0')

    return tryparse(
        Dates.DateTime,
        "$(m[1])T$(m[2]).$(millisecond)",
        Dates.dateformat"yyyy-mm-ddTHH:MM:SS.sss",
    )
end

@doc raw"""
    qci_status_timestamp(job_status, prefix::AbstractString)

Read the single `job_status` timestamp whose key starts with `prefix` (for
example `"running_at_"`), returning `nothing` when `job_status` is not a
dictionary, when no key or more than one key matches, or when the value is not a
parseable timestamp. The key suffix is not pinned because it names the provider
encoding (`rfc3339nano` today).
"""
function qci_status_timestamp(job_status, prefix::AbstractString)
    job_status isa AbstractDict || return nothing

    matched = filter(key -> startswith(string(key), prefix), collect(keys(job_status)))

    length(matched) == 1 || return nothing

    return qci_parse_timestamp(job_status[only(matched)])
end

@doc raw"""
    qci_elapsed_seconds(job_status, from_prefix::AbstractString, to_prefix::AbstractString)

Seconds between two `job_status` timestamps, or `nothing` when either timestamp
is missing or unparseable, or when the interval runs backwards. Resolution is
milliseconds (see [`qci_parse_timestamp`](@ref)).
"""
function qci_elapsed_seconds(
    job_status,
    from_prefix::AbstractString,
    to_prefix::AbstractString,
)
    from_ts = qci_status_timestamp(job_status, from_prefix)
    to_ts   = qci_status_timestamp(job_status, to_prefix)

    (isnothing(from_ts) || isnothing(to_ts)) && return nothing

    elapsed = Dates.value(to_ts - from_ts) / 1000

    return elapsed < 0 ? nothing : elapsed
end

# The provider keys a submission's `problem_config` by problem type, with the
# input file id under a type-specific key: `sample-qubo` jobs (DIRAC-1) use
# `qubo_file_id` under `quadratic_unconstrained_binary_optimization`, and
# `sample-hamiltonian-integer` jobs (DIRAC-3) use `polynomial_file_id` under
# `qudit_hamiltonian_optimization`. `hamiltonian_file_id` is the client's
# deprecated spelling of the latter. A submission carries exactly one problem
# type, so scanning the whole `problem_config` reads the same id for either
# device without pinning the job type here.
const QCI_PROBLEM_FILE_ID_KEYS = ("qubo_file_id", "polynomial_file_id", "hamiltonian_file_id")

@doc raw"""
    qci_problem_file_id(response)

The uploaded problem-file id recorded on a job submission, or `nothing` when the
response carries no submission. Works for both the DIRAC-1 QUBO and DIRAC-3
polynomial job types.
"""
function qci_problem_file_id(response)
    problem_config = qci_response_field(
        response,
        "job_info",
        "job_submission",
        "problem_config",
    )

    problem_config isa AbstractDict || return nothing

    for config in values(problem_config)
        config isa AbstractDict || continue

        for key in QCI_PROBLEM_FILE_ID_KEYS
            file_id = get(config, key, nothing)

            isnothing(file_id) || return file_id
        end
    end

    return nothing
end

@doc raw"""
    qci_provider_error(response)

The provider's job-error diagnostic, or `nothing` when the response carries
none. An `ERRORED` job normally reports it, but the field is read defensively so
a job that errored without one still reaches the caller as `ERRORED` rather than
as an indexing error.
"""
function qci_provider_error(response)
    return qci_response_field(response, "job_info", "job_result", "error")
end

@doc raw"""
    qci_provider_metadata(response)

Normalized view of the provider fields QCIOpt preserves from a QCI job
response, as a `Dict{String,Any}` with these keys:

| Key                | Source in the provider response                          |
|:-------------------|:---------------------------------------------------------|
| `"status"`         | `status`                                                 |
| `"job_id"`         | `job_info.job_id`                                        |
| `"result_file_id"` | `job_info.job_result.file_id`                            |
| `"problem_file_id"`| `job_info.job_submission.problem_config.*.*_file_id`     |
| `"queue_time_sec"` | `job_info.job_status`, queued → running                  |
| `"run_time_sec"`   | `job_info.job_status`, running → completed               |
| `"total_time_sec"` | `job_info.job_status`, submitted → completed             |
| `"device_usage_sec"` | `job_info.job_result.device_usage_s`                   |
| `"error"`          | `job_info.job_result.error`                              |
| `"response"`       | the response itself, verbatim                            |

Every key is always present; a value the response does not carry is `nothing`,
so reading one field never depends on another being there. `"response"` keeps
the unnormalized job response reachable, since the provider may report fields
this table does not name.

This is the same provider information the QUBODrivers sampler publishes under
its own standardized keys; see `QCIOpt.DiracSampler` and the API reference for
the key-by-key correspondence.
"""
function qci_provider_metadata(response)
    job_status = qci_response_field(response, "job_info", "job_status")

    return Dict{String,Any}(
        "status"           => qci_response_field(response, "status"),
        "job_id"           => qci_response_field(response, "job_info", "job_id"),
        "result_file_id"   => qci_response_field(response, "job_info", "job_result", "file_id"),
        "problem_file_id"  => qci_problem_file_id(response),
        "queue_time_sec"   => qci_elapsed_seconds(job_status, "queued_at_", "running_at_"),
        "run_time_sec"     => qci_elapsed_seconds(job_status, "running_at_", "completed_at_"),
        "total_time_sec"   => qci_elapsed_seconds(job_status, "submitted_at_", "completed_at_"),
        "device_usage_sec" => qci_response_field(response, "job_info", "job_result", "device_usage_s"),
        "error"            => qci_provider_error(response),
        "response"         => response,
    )
end
