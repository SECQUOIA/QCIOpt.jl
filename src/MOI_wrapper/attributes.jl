#                           get set supports
# [x] SolverName	        Yes	No	No
function MOI.get(solver::Optimizer{T}, ::MOI.SolverName) where {T}
    device_type = MOI.get(solver, QCIOpt.DeviceType())

    return "QCI Optimizer ($device_type)"
end

# [ ] SolverVersion	        Yes	No	No
# [ ] RawSolver	            Yes	No	No
# [ ] Silent	            Yes	Yes	Yes
# [ ] TimeLimitSec	        Yes	Yes	Yes
# [ ] RawOptimizerAttribute	Yes	Yes	Yes
# [ ] NumberOfThreads	    Yes	Yes	Yes

# Custom Attributes
struct DeviceType <: MOI.AbstractOptimizerAttribute end

function MOI.get(solver::Optimizer{T}, ::QCIOpt.DeviceType) where {T}
    return solver.settings["device_type"]
end

@doc raw"""
    supports_device_type(device_type::AbstractString)::Bool

Tells wether the solver supports a given `device_type`.
"""
function supports_device_type(device_type::AbstractString)::Bool
    return device_type == "dirac-1" || device_type == "dirac-3"
end

function MOI.set(solver::Optimizer{T}, ::QCIOpt.DeviceType, device_type::AbstractString) where {T}
    @assert supports_device_type(device_type)

    solver.settings["device_type"] = String(device_type)

    return nothing
end
