module DiracSampler

import ..QCIOpt
import QUBODrivers
import QUBODrivers: MOI, QUBOTools, Sample, SampleSet

const DEFAULT_DEVICE_TYPE = "dirac-1"
const DEFAULT_JOB_TYPE = "sample-qubo"

function qci_client_version()
    return try
        QCIOpt.PythonCall.pyconvert(
            String,
            QCIOpt.PythonCall.pyimport("importlib.metadata").version("qci-client"),
        )
    catch
        nothing
    end
end

function _get_path(value, path::Tuple)
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

function _backend_value(result, key::String, default = nothing)
    if result isa AbstractDict
        return get(result, key, default)
    elseif result isa NamedTuple && key in string.(keys(result))
        return getproperty(result, Symbol(key))
    else
        return default
    end
end

function _duration_seconds(metrics, path_start::Tuple, path_end::Tuple)
    start_ns = _get_path(metrics, path_start)
    end_ns = _get_path(metrics, path_end)

    if start_ns isa Real && end_ns isa Real && end_ns >= start_ns
        return (Float64(end_ns) - Float64(start_ns)) / 1e9
    else
        return nothing
    end
end

function effective_time(response, metrics; device_type::AbstractString = DEFAULT_DEVICE_TYPE)
    runtime = _get_path(
        metrics,
        ("job_metrics", "time_ns", "device", device_type, "samples", "runtime"),
    )

    if runtime isa AbstractVector && all(item -> item isa Real, runtime)
        return sum(Float64, runtime) / 1e9
    end

    device_usage_s = _get_path(response, ("job_info", "job_result", "device_usage_s"))

    if device_usage_s isa Real
        return Float64(device_usage_s)
    end

    return 0.0
end

function termination_status(status)
    status == "COMPLETED" && return MOI.LOCALLY_SOLVED
    status == "CANCELLED" && return MOI.INTERRUPTED
    status == "ERRORED" && return MOI.OTHER_ERROR

    return MOI.OTHER_ERROR
end

function qci_qubo_matrix(
    ::Type{T},
    n::Integer,
    linear::AbstractDict,
    quadratic::AbstractDict,
    scale::Real,
) where {T}
    matrix = zeros(T, n, n)
    factor = convert(T, scale)

    for (i, coefficient) in linear
        matrix[Int(i), Int(i)] += factor * convert(T, coefficient)
    end

    for ((i, j), coefficient) in quadratic
        value = factor * convert(T, coefficient)
        row = Int(i)
        col = Int(j)

        if row == col
            matrix[row, col] += value
        else
            matrix[row, col] += value / 2
            matrix[col, row] += value / 2
        end
    end

    return matrix
end

function default_backend_runner(
    matrix::AbstractMatrix{T};
    api_token::AbstractString,
    num_samples::Integer,
    relaxation_schedule::Integer = 1,
    silent::Bool = false,
) where {T}
    device = QCIOpt.DIRAC_1{T}()
    file = QCIOpt.qci_data_file(matrix)
    file_id = QCIOpt.qci_upload_file(file; api_token, silent)
    job_body = QCIOpt.qci_build_job_body(
        device;
        file_id,
        api_token,
        silent,
        device_type = DEFAULT_DEVICE_TYPE,
        job_type = DEFAULT_JOB_TYPE,
        num_samples,
        relaxation_schedule,
    )
    response = QCIOpt.qci_process_job(job_body; api_token, verbose = !silent)
    job_id = _get_path(response, ("job_info", "job_id"))

    metrics = if job_id isa AbstractString
        try
            QCIOpt.qci_client(; api_token, silent = true) do client
                return client.get_job_metrics(; job_id) |> QCIOpt.jl_object
            end
        catch err
            Dict{String,Any}(
                "capture_error_type" => string(typeof(err)),
                "capture_error" => sprint(showerror, err),
            )
        end
    else
        nothing
    end

    return Dict{String,Any}(
        "response" => response,
        "metrics" => metrics,
        "qci_client_version" => qci_client_version(),
        "request" => Dict{String,Any}(
            "file_id" => file_id,
            "num_samples" => num_samples,
            "relaxation_schedule" => relaxation_schedule,
        ),
    )
end

@doc raw"""
    QCIOpt.DiracSampler.Optimizer{T}

QUBODrivers sampler interface for QCI DIRAC-1 QUBO sampling.

This sampler is additive to `QCIOpt.Optimizer`: the existing MOI wrapper remains
available for the broader QCI device interface, while this type exposes the
uniform QUBODrivers sampler contract used by benchmark harnesses.
"""
QUBODrivers.@setup Optimizer begin
    name = "QCI Dirac"
    version = v"0.1.0"
    attributes = begin
        NumberOfSamples["num_samples"]::Integer = 10
        DeviceType["device_type"]::String = DEFAULT_DEVICE_TYPE
        RelaxationSchedule["relaxation_schedule"]::Integer = 1
        APIToken["api_token"]::Union{String,Nothing} = nothing
        Silent["silent"]::Bool = false
        BackendRunner["backend_runner"]::Function = default_backend_runner
    end
end

function QUBODrivers.sample(sampler::Optimizer{T}) where {T}
    n, linear, quadratic, scale, offset = QUBOTools.qubo(sampler, :dict; sense = :min)

    num_samples = MOI.get(sampler, NumberOfSamples())
    final_num_samples = MOI.get(sampler, QUBODrivers.FinalNumberOfReads())
    device_type = MOI.get(sampler, DeviceType())
    relaxation_schedule = MOI.get(sampler, RelaxationSchedule())
    api_token = MOI.get(sampler, APIToken())
    silent = MOI.get(sampler, Silent())
    runner = MOI.get(sampler, BackendRunner())

    final_num_samples = isnothing(final_num_samples) ? num_samples : final_num_samples

    num_samples >= 1 || error("'num_samples' must be a positive integer")
    final_num_samples >= 1 || error("'final_num_reads' must be a positive integer")
    device_type == DEFAULT_DEVICE_TYPE || error("QCI Dirac sampler only supports 'dirac-1'")

    if isnothing(api_token)
        api_token = QCIOpt.qci_default_token()
    end

    isnothing(api_token) && error("QCI API Token is not defined.")

    matrix = qci_qubo_matrix(T, n, linear, quadratic, scale)
    backend = runner(
        matrix;
        api_token,
        num_samples = final_num_samples,
        relaxation_schedule,
        silent,
    )
    response = _backend_value(backend, "response")
    metrics = _backend_value(backend, "metrics")
    backend_version = _backend_value(backend, "qci_client_version", qci_client_version())
    request = _backend_value(backend, "request", Dict{String,Any}())

    samples = samples_from_response(T, response, linear, quadratic, scale, offset)
    metadata = metadata_from_response(
        response,
        metrics,
        request;
        backend_version,
        num_samples = sum(QUBOTools.reads(sample) for sample in samples),
        device_type,
    )

    return SampleSet{T}(samples, metadata; sense = :min, domain = :bool)
end

function samples_from_response(
    ::Type{T},
    response,
    linear::AbstractDict,
    quadratic::AbstractDict,
    scale::Real,
    offset::Real,
) where {T}
    results = response["results"]
    solutions = results["solutions"]
    counts = results["counts"]
    samples = Vector{Sample{T,Int}}(undef, length(solutions))

    for i in eachindex(solutions)
        state = round.(Int, solutions[i])
        value = convert(T, QUBOTools.value(state, linear, quadratic, scale, offset))
        reads = Int(counts[i])

        samples[i] = Sample{T,Int}(state, value, reads)
    end

    return samples
end

function metadata_from_response(
    response,
    metrics,
    request;
    backend_version,
    num_samples::Integer,
    device_type::AbstractString = DEFAULT_DEVICE_TYPE,
)
    status = response["status"]
    job_info = response["job_info"]
    job_status = get(job_info, "job_status", Dict{String,Any}())
    job_result = get(job_info, "job_result", Dict{String,Any}())
    job_submission = get(job_info, "job_submission", Dict{String,Any}())
    qubo_config = _get_path(
        job_info,
        ("job_submission", "problem_config", "quadratic_unconstrained_binary_optimization"),
    )
    problem_file_id = qubo_config isa AbstractDict ? get(qubo_config, "qubo_file_id", nothing) : nothing

    metadata = QUBODrivers._sampler_metadata(
        origin = "QCI Dirac @ qci-client",
        algorithm_name = "QCI Dirac",
        backend_name = "QCI Dirac",
        backend_version = backend_version,
        execution_mode = "cloud_sampling",
        optimizer_iterations = nothing,
        optimizer_evaluations = num_samples,
        number_of_reads = num_samples,
        final_number_of_reads = num_samples,
        status = status,
        termination_status = termination_status(status),
    )

    metadata["backend"]["device"] = device_type
    metadata["backend"]["job_id"] = get(job_info, "job_id", nothing)
    metadata["backend"]["result_file_id"] = get(job_result, "file_id", nothing)
    metadata["backend"]["problem_file_id"] = problem_file_id
    metadata["time"] = Dict{String,Any}(
        "effective" => effective_time(response, metrics; device_type),
        "provider_wall" => _duration_seconds(
            metrics,
            ("job_metrics", "time_ns", "wall", "start"),
            ("job_metrics", "time_ns", "wall", "end"),
        ),
        "provider_queue" => _duration_seconds(
            metrics,
            ("job_metrics", "time_ns", "wall", "queue", "start"),
            ("job_metrics", "time_ns", "wall", "queue", "end"),
        ),
        "provider_processing" => _duration_seconds(
            metrics,
            ("job_metrics", "time_ns", "wall", "processing", "start"),
            ("job_metrics", "time_ns", "wall", "processing", "end"),
        ),
        "device_usage" => get(job_result, "device_usage_s", nothing),
    )
    metadata["provider"] = Dict{String,Any}(
        "job_info" => job_info,
        "job_status" => job_status,
        "job_result" => job_result,
        "job_submission" => job_submission,
        "metrics" => metrics,
        "request" => request,
        "qci_client_version" => backend_version,
    )

    return metadata
end

end # module
