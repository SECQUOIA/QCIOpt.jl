module Dirac3

import MathOptInterface as MOI

const MOIU = MOI.Utilities

const VI     = MOI.variableIndex
const SAT{T} = MOI.ScalarAffineTerm
const SAF{T} = MOI.ScalarAffineFunction
const SQT{T} = MOI.ScalarQuadraticTerm
const SQF{T} = MOI.ScalarQuadraticFunction

include("MOI_wrapper.jl")

end # module Dirac3
