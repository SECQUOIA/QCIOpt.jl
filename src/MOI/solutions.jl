# All Optimizers must implement the following attributes:
# [x] PrimalStatus
# The devices are unconstrained samplers, so every returned sample is a feasible
# point. Out-of-bounds result indices report `MOI.NO_SOLUTION`, following the
# MathOptInterface convention for `PrimalStatus`.
function MOI.get(solver::Optimizer{T}, attr::MOI.PrimalStatus) where {T}
    if 1 <= attr.result_index <= MOI.get(solver, MOI.ResultCount())
        return MOI.FEASIBLE_POINT
    else
        return MOI.NO_SOLUTION
    end
end

# [x] DualStatus
# QCI devices are sampler backends for unconstrained models: no dual problem is
# formulated and no dual values are ever computed, so the dual status is always
# `MOI.NO_SOLUTION` regardless of the result index or termination status.
MOI.get(::Optimizer{T}, ::MOI.DualStatus) where {T} = MOI.NO_SOLUTION

# [x] RawStatusString
# `"OPTIMIZE_NOT_CALLED"` before a solve, and `"UNKNOWN"` for stored provider
# metadata that reports no status string, so a partial response reports itself
# as unrecognized (and so `MOI.OTHER_ERROR`) rather than raising here.
const QCI_UNKNOWN_STATUS = "UNKNOWN"

function MOI.get(solver::Optimizer{T}, ::MOI.RawStatusString) where {T}
    if isempty(solver.solution.metadata)
        return "OPTIMIZE_NOT_CALLED"
    else
        let status = qci_response_field(solver.solution.metadata, "status")
            return status isa AbstractString ? String(status) : QCI_UNKNOWN_STATUS
        end
    end
end

# [x] ResultCount
MOI.get(solver::Optimizer{T}, ::MOI.ResultCount) where {T} = length(solver.solution.samples)

# [x] TerminationStatus
@doc raw"""
    QCI_TERMINATION_STATUS

Mapping from the QCI provider job status to `MOI.TerminationStatusCode`:

| Provider status | MOI status           | Meaning                                             |
|:----------------|:---------------------|:----------------------------------------------------|
| `"COMPLETED"`   | `MOI.LOCALLY_SOLVED` | The sampler returned solutions (heuristic, no bound) |
| `"CANCELLED"`   | `MOI.INTERRUPTED`    | The job was cancelled before completion              |
| `"ERRORED"`     | `MOI.OTHER_ERROR`    | The provider reported a job error                    |
| `"QUEUED"`      | `MOI.OTHER_LIMIT`    | The solve ended while the job was still queued       |
| `"RUNNING"`     | `MOI.OTHER_LIMIT`    | The solve ended while the job was still running      |
| `"SUBMITTED"`   | `MOI.OTHER_LIMIT`    | The solve ended right after submission               |

The `QUEUED`/`RUNNING`/`SUBMITTED` states are non-terminal on the provider side:
the blocking client normally waits for a terminal state, so observing one of
them means the solve stopped before the provider finished. They map to
`MOI.OTHER_LIMIT` (a non-error early stop) with no results; the exact provider
state remains available through `MOI.RawStatusString`. Unrecognized status
strings map to `MOI.OTHER_ERROR`.
"""
const QCI_TERMINATION_STATUS = Dict{String,MOI.TerminationStatusCode}(
    "CANCELLED" => MOI.INTERRUPTED,
    "COMPLETED" => MOI.LOCALLY_SOLVED,
    "ERRORED"   => MOI.OTHER_ERROR,
    "QUEUED"    => MOI.OTHER_LIMIT,
    "RUNNING"   => MOI.OTHER_LIMIT,
    "SUBMITTED" => MOI.OTHER_LIMIT,
)

function MOI.get(solver::Optimizer{T}, ::MOI.TerminationStatus) where {T}
    if isempty(solver.solution.metadata)
        return MOI.OPTIMIZE_NOT_CALLED
    else
        let status = MOI.get(solver, MOI.RawStatusString())
            return get(QCI_TERMINATION_STATUS, status, MOI.OTHER_ERROR)
        end
    end
end

# [x] ObjectiveValue
# Objective values are recomputed locally by the device layer when results are
# parsed (`readjust_qubo_values` / `readjust_poly_values`): each sample's value
# is the original model objective evaluated at the returned point, including
# constant offsets and, for maximization, the sign flip that undoes the
# negation applied at submission. Invalid result indices throw
# `MOI.ResultIndexBoundsError`.
function MOI.get(solver::Optimizer{T}, attr::MOI.ObjectiveValue) where {T}
    MOI.check_result_index_bounds(solver, attr)

    return solver.solution.samples[attr.result_index].value
end

# [x] SolveTimeSec
@doc raw"""
    qci_get_elapsed_time(job_status)

Seconds the provider spent running a job, from its `running_at_` to its
`completed_at_` job-status timestamp, or `NaN` when the timestamps are missing or
unusable. `NaN` is the same value `MOI.SolveTimeSec` reports for a job that did
not complete, so a completed job whose timing the provider did not report leaves
the rest of the solution readable.
"""
function qci_get_elapsed_time(job_status)
    return something(
        qci_elapsed_seconds(job_status, "running_at_", "completed_at_"),
        NaN,
    )
end

function MOI.get(solver::Optimizer{T}, ::MOI.SolveTimeSec) where {T}
    # "total elapsed solution time (in seconds) as reported by the optimizer"
    if MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED # means it was completed successfully
        return qci_get_elapsed_time(
            qci_response_field(solver.solution.metadata, "job_info", "job_status"),
        )
    else
        return NaN
    end
end

# [x] VariablePrimal
function MOI.get(solver::Optimizer{T}, attr::MOI.VariablePrimal, vi::VI) where {T}
    MOI.check_result_index_bounds(solver, attr)

    i = var_idx(solver.device.varmap, vi)

    return solver.solution.samples[attr.result_index].point[i]
end

struct ResultMultiplicity <: MOI.AbstractOptimizerAttribute
    result_index::Int

    function ResultMultiplicity(result_index::Integer = 1)
        @assert result_index >= 1

        return new(result_index)
    end
end

function MOI.get(solver::Optimizer{T}, attr::ResultMultiplicity) where {T}
    MOI.check_result_index_bounds(solver, attr)

    return solver.solution.samples[attr.result_index].reads
end

MOI.is_set_by_optimize(::ResultMultiplicity) = true

@doc raw"""
    ProviderMetadata()

Optimizer attribute holding the provider metadata preserved from the QCI job
response of the last solve, for both DIRAC-1 and DIRAC-3.

`MOI.get(solver, QCIOpt.ProviderMetadata())` returns the normalized dictionary
documented on [`qci_provider_metadata`](@ref): job identity, provider status,
job-status timing, result and problem file ids, the provider's job-error
diagnostic, and the job response itself under `"response"`. Every key is always
present and is `nothing` when the response does not carry it, including before
`optimize!` has been called.

The provider status is also available as `MOI.RawStatusString`, and the running
time as `MOI.SolveTimeSec`; this attribute is the only access to the remaining
fields.
"""
struct ProviderMetadata <: MOI.AbstractOptimizerAttribute end

function MOI.get(solver::Optimizer{T}, ::ProviderMetadata) where {T}
    return qci_provider_metadata(solver.solution.metadata)
end

MOI.is_set_by_optimize(::ProviderMetadata) = true

# A `CachingOptimizer` — what `JuMP.Model(QCIOpt.Optimizer)` wraps this in —
# maps every optimizer-attribute value it returns through `map_indices`, which
# has no method for a `Dict{String,Any}`. The value carries no MOI indices, so
# it passes through unchanged, as `MOI.RawOptimizerAttribute` values do.
MOIU.map_indices(::Any, ::ProviderMetadata, value) = value
