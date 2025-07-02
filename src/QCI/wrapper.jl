include("error.jl")
include("client.jl")
include("device.jl")
include("data.jl")
include("jobs.jl")

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

qci_default_attributes(::Type{T}, spec::AbstractString) where {T} = qci_default_attributes(qci_device_type(T, spec))
qci_default_attributes(::D) where {D<:QCI_DEVICE}                 = qci_default_attributes(D)
qci_default_attributes(::Type{D}) where {D<:QCI_DEVICE}           = qci_default_attributes()

qci_default_attributes() = Dict{String,Any}(
    "api_token" => qci_default_token(),
    "file_name" => nothing,
    "silent"    => false,
)

@doc raw"""
    qci_is_free_tier
"""
function qci_is_free_tier(; url::AbstractString = QCI_URL, api_token::AbstractString = qci_default_token())
    alloc = qci_get_allocations(; url, api_token)

    return !(alloc["dirac"]["paid"])
end
