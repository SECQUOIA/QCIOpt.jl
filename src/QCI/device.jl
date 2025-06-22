
@doc raw"""
    QCI_DEVICE

Abstract type to represent QCI devices.
"""
abstract type QCI_DEVICE end

@doc raw"""
    QCI_DIRAC <: QCI_DEVICE

Abstract type to represent QCI devices of the Dirac family.
"""
abstract type QCI_DIRAC <: QCI_DEVICE end

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
