using Test
using Dirac3
using JuMP
using QUBODrivers

const API_TOKEN = ""

QUBODrivers.test(Dirac3.Optimizer) do model
    MOI.set(model, Dirac3.NumberOfReads(), 1) # to go faster >>>
    # MOI.set(model, Dirac3.APIToken(), API_TOKEN)
end
