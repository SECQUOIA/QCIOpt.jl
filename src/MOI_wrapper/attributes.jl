#                           get set supports
# [x] SolverName	        Yes	No	No
function MOI.get(solver::Optimizer{T}, ::MOI.SolverName) where {T}
    device_type = MOI.get(solver, QCIOpt.DeviceType())

    return "QCI Optimizer ($device_type)"
end

# [x] SolverVersion	        Yes	No	No
function MOI.get(::Optimizer{T}, ::MOI.SolverVersion) where {T}
    return v"4.5.0"     #qci-client version
end

### Check below for the list of attributes that are supported by the QCI Optimizer and create functions - YP 

# [ ] RawSolver	            Yes	No	No   - maybe there is none, should return nothing if so (or the optimizer itself/solver variable)
function MOI.get(::Optimizer{T}, ::MOI.RawSolver) where {T}
    return nothing
end


# [ ] Silent	            Yes	Yes	Yes     - check on QCI on how to suppress output, return that it's not supported if not; 
# [ ] TimeLimitSec	        Yes	Yes	Yes     - check on QCI on how long you allow the solver to run, if not, no support also; might be device dependent; may need to differentiate among the solvers- if tricky do last. 
# [ ] RawOptimizerAttribute	Yes	Yes	Yes     - select optimizer based on string? skip for now 

# [x] NumberOfThreads	    Yes	Yes	Yes  
MOI.supports(::Optimizer{T}, ::MOI.NumberOfThreads) where {T} = false # thread is not configurable by the user 

# Custom Attributes
struct DeviceType <: MOI.AbstractOptimizerAttribute end

function MOI.get(solver::Optimizer{T}, ::QCIOpt.DeviceType) where {T}
    return solver.settings["device_type"]
end

@doc raw"""
    supports_device_type(device_type::AbstractString)::Bool

Tells whether the solver supports a given `device_type`.
"""
function supports_device_type(device_type::AbstractString)::Bool
    return device_type == "dirac-1" || device_type == "dirac-3"
end

function MOI.set(solver::Optimizer{T}, ::QCIOpt.DeviceType, device_type::AbstractString) where {T}
    @assert supports_device_type(device_type)

    solver.settings["device_type"] = String(device_type)

    return nothing
end

MOI.supports(::Optimizer{T}, ::QCIOpt.DeviceType) where {T} = true
