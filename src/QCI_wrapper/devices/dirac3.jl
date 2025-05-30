@doc raw"""
    DIRAC_3 <: QCI_DIRAC <: QCI_DEVICE

## About

"""
struct DIRAC_3 <: QCI_DIRAC end

QCI_DEVICES["dirac-3"] = DIRAC_3

const DIRAC_3_ATTRIBUTES = Set{String}([
    "num_samples",
    "relaxation_schedule",
])

qci_default_attributes(::DIRAC_3) = Dict{String,Any}(
    qci_default_attributes()...,
    "device_type"         => "dirac-3",
    "num_samples"         => 10,
    "relaxation_schedule" => 1,
)

qci_supports_attribute(::DIRAC_3, attr::AbstractString) = attr ∈ DIRAC_3_ATTRIBUTES
