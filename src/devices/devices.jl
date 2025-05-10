@doc raw"""
    QCI_DEVICE

## Available device types:

- [`DIRAC_1`](@ref)
- [`DIRAC_2`](@ref)
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

Tells wether the solver supports a given device `spec`.
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

    return QciClient(; url, api_token)
end

function qci_client(
    callback::Function,
    device::Union{QCI_DEVICE,Nothing}        = nothing;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = QCI_TOKEN[],
)
    return try
        client = qci_client(; url, api_token)

        result = callback(client, device)

        # TODO: Wrap-up

        return result
    catch e
        # TODO: Wrap-up

        rethrow(e)
    finally
        return nothing
    end
end

include("dirac1.jl")
include("dirac2.jl")
include("dirac3.jl")
