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

function MOI.set(solver::Optimizer{T}, ::QCIOpt.DeviceType, spec::AbstractString) where {T}
    qci_supports_device(spec) || throw(UnsupportedDevice(spec))

    solver.settings["device_type"] = String(spec)

    return nothing
end

MOI.supports(::Optimizer{T}, ::QCIOpt.DeviceType) where {T} = true

struct APIToken <: MOI.AbstractOptimizerAttribute end

function MOI.get(solver::Optimizer{T}, ::QCIOpt.APIToken) where {T}
    return solver.settings["api_token"]
end

function MOI.set(solver::Optimizer{T}, ::QCIOpt.APIToken, api_token::AbstractString) where {T}
    solver.settings["api_token"] = String(api_token)

    return nothing
end

function MOI.set(solver::Optimizer{T}, ::QCIOpt.APIToken, ::Nothing) where {T}
    solver.settings["api_token"] = nothing
    
    return nothing
end

MOI.supports(::Optimizer{T}, ::QCIOpt.APIToken) where {T} = true
