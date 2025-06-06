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

# [x] RawSolver	            Yes	No	No   - maybe there is none, should return nothing if so (or the optimizer itself/solver variable)
function MOI.get(::Optimizer{T}, ::MOI.RawSolver) where {T}
    # return opt.qci_client
    return nothing
end

# [ ] Silent	            Yes	Yes	Yes     - check on QCI on how to suppress output, return that it's not supported if not; 
# TODO: use redirect_stdout to suppress output? 
function MOI.get(solver::Optimizer{T}, ::MOI.Silent) where {T}
    return solver.attributes["silent"]
end

function MOI.set(solver::Optimizer{T}, ::MOI.Silent, silent::Bool) where {T}
    solver.attributes["silent"] = silent

    return nothing
end

MOI.supports(::Optimizer{T}, ::MOI.Silent) where {T} = true

# [x] TimeLimitSec	        Yes	Yes	Yes     - check on QCI on how long you allow the solver to run, if not, no support also; might be device dependent; may need to differentiate among the solvers- if tricky do last. 
MOI.supports(::Optimizer{T}, ::MOI.TimeLimitSec) where {T} = false

# [ ] RawOptimizerAttribute	Yes	Yes	Yes     - select optimizer based on string? skip for now
function MOI.get(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    @assert MOI.supports(solver, attr)

    return solver.attributes[attr.name]
end

function MOI.set(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute, value) where {T}
    @assert MOI.supports(solver, attr)

    if attr.name == "device_type"
        # Treat this as a special case as this modifies the supported attributes
        MOI.set(solver, DeviceType(), value)
    else
        solver.attributes[attr.name] = value
    end
end

function MOI.supports(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    if attr.name ∈ QCI_GENERIC_ATTRIBUTES
        return true
    else
        device = QCIOpt.qci_device(MOI.get(solver, QCIOpt.DeviceType()))::QCI_DEVICE

        return qci_supports_attribute(device, attr.name)
    end
end

# [x] NumberOfThreads	    Yes	Yes	Yes  
MOI.supports(::Optimizer{T}, ::MOI.NumberOfThreads) where {T} = false # thread is not configurable by the user 

# Custom Attributes
struct DeviceType <: MOI.AbstractOptimizerAttribute end

function MOI.get(solver::Optimizer{T}, ::QCIOpt.DeviceType) where {T}
    return solver.attributes["device_type"]
end

function MOI.set(solver::Optimizer{T}, ::QCIOpt.DeviceType, spec::AbstractString) where {T}
    qci_supports_device(spec) || throw(UnsupportedDevice(spec))

    copy!(solver.attributes, qci_default_attributes(spec))

    return nothing
end

MOI.supports(::Optimizer{T}, ::QCIOpt.DeviceType) where {T} = true

# # Extra Attributes

# # [ ] ObjectiveSense
# function MOI.get(::Optimizer{T}, ::MOI.ObjectiveSense) where {T}
#     return MOI.MIN_SENSE
# end

# function MOI.set(::Optimizer{T}, ::MOI.ObjectiveSense, value::MOI.OptimizationSense) where {T}
#     @assert value === MOI.MIN_SENSE

#     return nothing
# end

# MOI.supports(::Optimizer{T}, ::MOI.ObjectiveSense) where {T} = true
