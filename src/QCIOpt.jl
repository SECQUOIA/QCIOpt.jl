module QCIOpt

using LinearAlgebra

import QUBODrivers
import QUBOTools
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

function __init__()
    PythonCall.pycopy!(np, PythonCall.pyimport("numpy"))
    PythonCall.pycopy!(qcic, PythonCall.pyimport("qci_client"))

    return nothing
end

const QCI_URL = raw"https://api.qci-prod.com"

include("MOI_wrapper/MOI_wrapper.jl")

# include("sampler.jl")

end # module QCIOpt
