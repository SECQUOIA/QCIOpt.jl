@doc raw"""
    QCI_DEVICE

## Available device types:

- [`DIRAC_3`](@ref)

"""
abstract type QCI_DEVICE end

const QCI_DEVICES = Dict{String,Type{<:QCI_DEVICE}}()

@doc raw"""
    qci_device(spec::AbstractString; kwargs...)
"""
function qci_device end

function qci_device(spec::AbstractString; kwargs...)
    @assert qci_supports_device(spec)

    type = qci_device_type(spec)::Type{<:QCI_DEVICE}

    return type(; kwargs...)
end

@doc raw"""
    qci_device_type(spec::AbstractString)

Returns the equivalent [`QCI_DEVICE`](@ref) type to a given `spec` string.
"""
function qci_device_type end

qci_device_type(spec::AbstractString) = get(QCI_DEVICES, String(spec), nothing)

@doc raw"""
    qci_supports_device(spec::AbstractString)::Bool

Tells whether the solver supports a given device `spec`.
"""
function qci_supports_device end

function qci_supports_device(spec::AbstractString)
    return haskey(QCI_DEVICES, String(spec))
end

@doc raw"""
    qci_supported_devices
"""
function qci_supported_devices end

qci_supported_devices() = sort!(collect(keys(QCI_DEVICES)))

struct UnsupportedDevice <: Exception
    spec::String
end

function Base.showerror(io::IO, e::UnsupportedDevice)
    specs = join(map(s -> "'$s'", qci_supported_devices()), ", ", " and ")

    println(io, "Unsupported device specification: '$(e.spec)'. Options are: $(specs).")
end

@doc raw"""
    qci_client()

## Example

```julia
QCIOpt.qci_client(QCIOpt.qci_device("dirac-3")) do (client, device)
    @show device
    @show client.get_allocations()
end
```
"""
function qci_client end

function qci_client(;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = QCI_TOKEN[],
)
    @assert !isnothing(api_token) "API Token was not provided."

    return qcic.QciClient(; url, api_token)
end

abstract type QCI_ERROR <: Exception end

struct QCI_HTTP_ERROR <: QCI_ERROR
    code::Int
    msg::String
end

function Base.showerror(io::IO, qci_err::QCI_HTTP_ERROR)
    if qci_err.code == 401 && qci_err.msg == "Unauthorized"
        println(io, "HTTP Error $(qci_err.code): QCI: Unauthorized API Token")
    else
        println(oi, "HTTP Error $(qci_err.code): $(qci_err.msg)")
    end
end

function qci_parse_error(err)
    if err isa PythonCall.PyException
        PythonCall.pyisinstance(err, requests.exceptions.HTTPError) || return nothing
        PythonCall.pyhasattr(err, "args")                           || return nothing

        let args = PythonCall.pygetattr(err, "args")
            PythonCall.pylen(args) == 1 || return nothing

            let msg = only(args)
                PythonCall.pyisinstance(msg, PythonCall.pytype(PythonCall.pystr(""))) || return nothing
                
                let m = match(
                        r"([0-9]+) Client Error: Unauthorized for url: (.*) with response body: (.*)",
                        PythonCall.pyconvert(String, msg),
                    )
                    isnothing(m) && return nothing

                    code     = parse(Int, m[1])
                    response = JSON.parse(m[3])

                    return QCI_HTTP_ERROR(code, String(response["message"]))
                end
            end
        end
    end

    return nothing
end

function qci_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = QCI_TOKEN[],
    silent::Bool                             = false,
)
    return try
        client = qci_client(; url, api_token)

        result = if silent
            redirect_stdout(() -> callback(client), devnull)
        else
            callback(client)
        end

        return result
    catch err
        qci_err = qci_parse_error(err)

        if !isnothing(qci_err)
            rethrow(qci_err)
        end

        rethrow(err)    
    end
end

function qci_get_allocations(; url = QCI_URL, api_token = QCI_TOKEN[], silent = false)
    alloc = QCIOpt.qci_client(; url, api_token, silent) do client
        return client.get_allocations() |> jl_object
    end

    return alloc["allocations"]
end

@doc raw"""
    QCI_QUBO_DATA{T}
"""
struct QCI_QUBO_DATA{T}
    data::Matrix{T}
end

function qci_qubo_data(Q::AbstractMatrix{T}) where {T}
    m, n = size(Q)

    @assert m == n
    @assert issymmetric(Q)

    return QCI_QUBO_DATA{T}(Q)
end

function qci_data_file(Q::AbstractMatrix{T}; file_name::Union{AbstractString,Nothing} = nothing) where {T}
    qubo = qci_qubo_data(Q)
    file = Dict{String,Any}(
        "file_name"   => "smallest_objective.json",
        "file_config" => Dict{String,Any}(
            "qubo" => Dict{String,Any}(
                "data" => np.array(qubo.data),
            )
        )
    )

    if !isnothing(file_name)
        open(file_name, "w") do io
            println(io, JSON.json(file, 4))
        end
    end

    return file
end

@doc raw"""
    QCI_POLY_DATA{T}
"""
struct QCI_POLY_DATA{T}
    num_variables::Int
    min_degree::Int
    max_degree::Int
    data::Vector{Dict{String,Any}}
end

function qci_poly_data(indices::AbstractVector{V}, values::AbstractVector{T}) where {T,V<:AbstractVector{<:Integer}}
    @assert length(indices) == length(values)

    first_iter    = true
    term_size     = nothing
    num_variables = 0
    min_degree    = nothing
    max_degree    = nothing
    data          = Dict{String,Any}[]

    for (idx, val) in zip(indices, values)
        if first_iter
            term_size     = length(idx)
            num_variables = maximum(idx)
            degree        = count(i -> i > 0, idx)
            min_degree    = degree
            max_degree    = degree

            first_iter    = false
        else
            @assert length(idx) == term_size

            num_variables = max(num_variables, maximum(idx))
            degree        = count(i -> i > 0, idx)
            min_degree    = min(min_degree, degree)
            max_degree    = max(max_degree, degree)
        end

        push!(data, Dict{String,Any}("idx" => idx, "val" => val))
    end

    return QCI_POLY_DATA{T}(
        num_variables,
        min_degree,
        max_degree,
        data,
    )
end

function qci_data_file(indices, values; file_name::Union{AbstractString,Nothing} = nothing)
    poly = qci_poly_data(indices, values)
    file = Dict{String,Any}(
        "file_name"   => something(file_name, ""),
        "file_config" => Dict{String,Any}(
            "polynomial" => Dict{String,Any}(
                "num_variables" => poly.num_variables,
                "min_degree"    => poly.min_degree,
                "max_degree"    => poly.max_degree,
                "data"          => poly.data,
            )
        )
    )

    if !isnothing(file_name)
        open(file_name, "w") do io
            println(io, JSON.json(file, 4))
        end
    end

    return file
end

function qci_data_file(varmap::Function, p::DP.Polynomial{_V,_M,T}; file_name::Union{AbstractString,Nothing} = nothing) where {_V,_M,T}
    indices = Vector{Int}[]
    values  = T[]
    degree  = DP.maxdegree(p)

    for t in DP.terms(p)
        val = DP.coefficient(t)
        idx = sizehint!(Int[], degree)

        for (v, d) in DP.powers(t)
            i = varmap(v)::Integer

            for _ = 1:d
                push!(idx, i)
            end
        end

        if length(idx) == 0 # skip constant terms
            continue
        end

        while length(idx) < degree
            push!(idx, 0)
        end

        push!(indices, sort!(idx))
        push!(values, val)
    end

    return qci_data_file(indices, values; file_name)
end

function qci_data_file(p::DP.Polynomial{T}; file_name::Union{AbstractString,Nothing} = nothing) where {T}
    varmap = Dict{DP.Variable,Int}(x => i for (i, x) in enumerate(DP.variables(p)))

    return qci_data_file(x -> varmap[x]::Int, p; file_name)
end

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
    relaxation_schedule::Integer = 1,
    num_samples::Integer         = 100,
    num_levels::AbstractVector{U}, # This needs to be adjusted per-variable
) where {U<:Integer}
    job_tags   = String[]
    job_params = Dict{String,Any}(
        "device_type"         => device_type,
        "num_samples"         => num_samples,
        "relaxation_schedule" => relaxation_schedule,
        "num_levels"          => num_levels,
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

function qci_build_qubo_job_body(
    file_id::AbstractString;
    # Client Arguments
    url       = QCI_URL,
    api_token = QCI_TOKEN[],
    silent    = false,
    # Job Arguments
    device_type::AbstractString,
    job_type::AbstractString,
    num_samples::Integer         = 100,
)
    job_tags   = String[]
    job_params = Dict{String,Any}(
        "device_type"         => device_type,
        "num_samples"         => num_samples,
    )

    return qci_client(; url, api_token, silent) do client
        client.build_job_body(;
            job_type   = job_type,
            job_name   = "",
            job_tags   = py_object(job_tags),
            job_params = py_object(job_params),
            qubo_file_id = file_id,
        ) |> jl_object
    end
end

function qci_process_job(job_body; url = QCI_URL, api_token = QCI_TOKEN[], verbose::Bool = true)
    return qci_client(; url, api_token) do client
        client.process_job(;
            job_body = py_object(job_body),
            verbose,
        ) |> jl_object
    end
end

function qci_get_results(::Type{U}, ::Type{T}, response) where {U, T}
    if response["status"] == "COMPLETED"
        res = response["results"]

        samples = map(
            (x, v, r) -> Sample{U,T}(Vector{U}(x), convert(T, v), r),
            res["solutions"],
            res["energies"],
            res["counts"],
        )

        return Solution{U,T}(samples, response)
    elseif response["status"] == "ERRORED"
        @error(response["job_info"]["job_result"]["error"])

        return Solution{U,T}(Sample{U,T}[], response)
    else
        return Solution{U,T}(Sample{U,T}[], response)
    end
end

const QCI_GENERIC_ATTRIBUTES = Set{String}([
    "device_type",
    "file_name",
    "api_token",
    "slient",
])

@doc raw"""
    qci_supports_attribute
"""
function qci_supports_attribute end

qci_supports_attribute(::QCI_DEVICE, ::AbstractString) = false

function qci_default_attributes end

qci_default_attributes(spec::AbstractString) = qci_default_attributes(qci_device(spec))
qci_default_attributes(::QCI_DEVICE)         = qci_default_attributes()

qci_default_attributes() = Dict{String,Any}(
    "api_token" => QCI_TOKEN[],
    "file_name" => nothing,
    "silent"    => false,
)

@doc raw"""
    QCI_DIRAC <: QCI_DEVICE
"""
abstract type QCI_DIRAC <: QCI_DEVICE end

@doc raw"""
    qci_is_free_tier
"""
qci_is_free_tier() = true # TODO: figure out if there is any specific call to the API that can tell this status
