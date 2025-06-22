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

qci_default_attributes(spec::AbstractString) = qci_default_attributes(qci_device(spec))
qci_default_attributes(::QCI_DEVICE)         = qci_default_attributes()

qci_default_attributes() = Dict{String,Any}(
    "api_token" => QCI_TOKEN[],
    "file_name" => nothing,
    "silent"    => false,
)

@doc raw"""
    qci_is_free_tier
"""
qci_is_free_tier() = true # TODO: figure out if there is any specific call to the API that can tell this status
