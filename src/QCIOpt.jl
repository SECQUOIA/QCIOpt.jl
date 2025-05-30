module QCIOpt

using LinearAlgebra
using JSON

import MathOptInterface as MOI
import DynamicPolynomials as DP

const PolyVar = DP.Variable{DP.Commutative{DP.CreationOrder},DP.Graded{DP.LexOrder}}
const Poly{T} = DP.Polynomial{DP.Commutative{DP.CreationOrder},DP.Graded{DP.LexOrder},T}

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

const np       = PythonCall.pynew()
const qcic     = PythonCall.pynew()
const json     = PythonCall.pynew()
const requests = PythonCall.pynew()

const QCI_URL   = raw"https://api.qci-prod.com"
const QCI_TOKEN = Ref{Union{String,Nothing}}(nothing)

function __init__()
    PythonCall.pycopy!(np, PythonCall.pyimport("numpy"))
    PythonCall.pycopy!(qcic, PythonCall.pyimport("qci_client"))
    PythonCall.pycopy!(json, PythonCall.pyimport("json"))
    PythonCall.pycopy!(requests, PythonCall.pyimport("requests"))

    __auth__()

    return nothing
end

function __auth__()
    qci_token = get(ENV, "QCI_TOKEN", nothing)

    if isnothing(qci_token)
        @warn """
        Environment variable 'QCI_TOKEN' is not defined.
        You can still provide it as an attribute to `QCIOpt.Optimizer` before calling `optimize!`
        """
    else
        QCI_TOKEN[] = qci_token
    end

    return nothing
end

function jl_object(py_obj)
    # Convert Python object to JSON string, then parse it into a Julia object
    js_data = PythonCall.pyconvert(String, json.dumps(py_obj))

    return JSON.parse(js_data)
end

function py_object(jl_obj)
    # Convert Python object to JSON string, then parse it into a Julia object
    js_data = PythonCall.pystr(JSON.json(jl_obj))

    return json.loads(js_data)
end

# Device Interface
include("QCI_wrapper/QCI_wrapper.jl")

# MOI Wrappers
include("MOI_wrapper/MOI_wrapper.jl")

# include("sampler.jl")

end # module QCIOpt
