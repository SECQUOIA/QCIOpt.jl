
function qci_upload_file(file; url = QCI_URL, api_token = QCI_TOKEN[], silent = false)
    response = qci_client(; url, api_token, silent) do client
        client.upload_file(; file = py_object(file)) |> jl_object
    end

    return response["file_id"]
end

function qci_build_poly_job_body(
    file_id::AbstractString;
    # Client Arguments
    url       = QCI_URL,
    api_token = QCI_TOKEN[],
    silent    = false,
    # Job Arguments
    device_type::AbstractString,
    job_type::AbstractString,
    num_samples::Integer         = 100,
    num_levels::AbstractVector{U}, # This needs to be adjusted per-variable
    relaxation_schedule::Integer = 1,
) where {U<:Integer}
    job_tags   = String[]
    job_params = Dict{String,Any}(
        "device_type"         => device_type,
        "num_samples"         => num_samples,
        "num_levels"          => num_levels,
        "relaxation_schedule" => relaxation_schedule,
    )

    return qci_client(; url, api_token, silent) do client
        client.build_job_body(;
            job_type   = job_type,
            job_name   = "",
            job_tags   = py_object(job_tags),
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

function qci_process_job(job_body; url = QCI_URL, api_token = QCI_TOKEN[], verbose::Bool = true)
    return qci_client(; url, api_token) do client
        client.process_job(;
            job_body = py_object(job_body),
            verbose,
        ) |> jl_object
    end
end
