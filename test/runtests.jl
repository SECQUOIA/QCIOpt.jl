using Test
using JuMP
using QCIOpt
using QUBODrivers

# const API_TOKEN = ""

QUBODrivers.test(QCIOpt.Optimizer) do model
    MOI.set(model, QCIOpt.NumberOfReads(), 1) # to go faster >>>
    # MOI.set(model, QCIOpt.APIToken(), API_TOKEN)
end
