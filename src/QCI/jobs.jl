
function qci_upload_file(file; url = QCI_URL, api_token = qci_default_token(), silent = false)
    response = qci_client(; url, api_token, silent) do client
        client.upload_file(; file = py_object(file)) |> jl_object
    end

    return response["file_id"]
end

@doc raw"""
    qci_build_poly_job_body(file_id; device_type, job_type, num_levels, sum_constraint, kwargs...)

Build a QCI polynomial job body from explicit client and job arguments.
`num_levels` configures an integer-qudit job, while `sum_constraint` configures
a continuous normalized-qudit job.
"""
function qci_build_poly_job_body(
    file_id::AbstractString;
    # Client Arguments
    url       = QCI_URL,
    api_token = qci_default_token(),
    silent    = false,
    # Job Arguments
    device_type::AbstractString,
    job_type::AbstractString,
    num_samples::Integer         = 100,
    num_levels::Union{AbstractVector{<:Integer},Nothing} = nothing,
    sum_constraint::Union{Real,Nothing} = nothing,
    relaxation_schedule::Integer = 1,
    job_name::AbstractString = "",
    job_tags::AbstractVector{<:AbstractString} = String[],
)
    job_params = Dict{String,Any}(
        "device_type"         => device_type,
        "num_samples"         => num_samples,
        "relaxation_schedule" => relaxation_schedule,
    )

    isnothing(num_levels) || (job_params["num_levels"] = num_levels)
    isnothing(sum_constraint) || (job_params["sum_constraint"] = sum_constraint)

    return qci_client(; url, api_token, silent) do client
        client.build_job_body(;
            job_type   = job_type,
            job_name   = String(job_name),
            job_tags   = py_object(String[String(tag) for tag in job_tags]),
            job_params = py_object(job_params),
            polynomial_file_id = file_id,
        ) |> jl_object
    end
end

function qci_build_job_body(device_type::AbstractString, job_type::AbstractString; kwargs...)
    return qci_build_job_body(Symbol(device_type), Symbol(job_type); kwargs...)
end

function qci_build_job_body(device_type::Symbol, job_type::Symbol; kwargs...)
    return qci_build_job_body(Val(device_type), Val(job_type); kwargs...)
end

function qci_build_job_body(::Val{device_type}, ::Val{job_type}; kwargs...) where {device_type, job_type}
    error("Unknown job type: '$job_type' for device '$device_type'. Options are ")

    return nothing
end

@doc raw"""
    qci_process_job(job_body; url = QCI_URL, api_token = qci_default_token(), silent = false, verbose = !silent)

Submit and process a QCI job. When `silent` is true, provider console output is
captured and not displayed; the same setting disables the client's progress
messages by default.
"""
function qci_process_job(
    job_body;
    url = QCI_URL,
    api_token = qci_default_token(),
    silent::Bool = false,
    verbose::Bool = !silent,
)
    return qci_client(; url, api_token, silent) do client
        client.process_job(;
            job_body = py_object(job_body),
            verbose,
        ) |> jl_object
    end
end
