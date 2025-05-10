module QCIOpt

using LinearAlgebra

import MathOptInterface as MOI

const MOIU    = MOI.Utilities
const VI      = MOI.VariableIndex
const CI{F,S} = MOI.ConstraintIndex{F,S}
const EQ{T}   = MOI.EqualTo{T}
const LT{T}   = MOI.LessThan{T}
const GT{T}   = MOI.GreaterThan{T}
const SAT{T}  = MOI.ScalarAffineTerm
const SAF{T}  = MOI.ScalarAffineFunction
const SQT{T}  = MOI.ScalarQuadraticTerm
const SQF{T}  = MOI.ScalarQuadraticFunction

import PythonCall

const np   = PythonCall.pynew()
const qcic = PythonCall.pynew()

const QCI_TOKEN = Ref{Union{String,Nothing}}(nothing)

function __auth__()
    qci_token = get(ENV, "CQI_TOKEN", nothing)

    if isnothing(qci_token)
        @warn """
        Environment variable 'CQI_TOKEN' is not defined.
        You can still provide it as an attribute to `QCIOpt.Optimizer` before calling `optimize!`
        """
    else
        QCI_TOKEN[] = qci_token
    end

    return nothing
end

function __init__()
    PythonCall.pycopy!(np, PythonCall.pyimport("numpy"))
    PythonCall.pycopy!(qcic, PythonCall.pyimport("qci_client"))

    __auth__()

    return nothing
end

const QCI_URL = raw"https://api.qci-prod.com"

# Device Interface
include("devices/devices.jl")

# MOI Wrappers
include("MOI_wrapper/MOI_wrapper.jl")

# include("sampler.jl")

end # module QCIOpt
