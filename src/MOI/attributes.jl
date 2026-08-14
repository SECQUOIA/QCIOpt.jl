@doc raw"""
    DeviceType()

Optimizer attribute selecting the QCI device backend. Supported values are the
keys returned by [`qci_supported_devices`](@ref), such as `"dirac-1"` and
`"dirac-3"`.
"""
struct DeviceType <: MOI.AbstractOptimizerAttribute end

#                           get set supports
# [x] SolverName	        Yes	No	No
function MOI.get(solver::Optimizer{T}, ::MOI.SolverName) where {T}
    device_type = MOI.get(solver, QCIOpt.DeviceType())

    return "QCI Optimizer ($device_type)"
end

# [x] SolverVersion	        Yes	No	No
function MOI.get(::Optimizer{T}, ::MOI.SolverVersion) where {T}
    return pkgversion(QCIOpt)
end

# MIN_SENSE and MAX_SENSE are accepted; FEASIBILITY_SENSE is rejected with an
# actionable error at optimize time because MOI capability queries cannot
# distinguish individual ObjectiveSense values.
MOI.supports(::Optimizer, ::MOI.ObjectiveSense) = true

### Check below for the list of attributes that are supported by the QCI Optimizer and create functions - YP 

# [x] RawSolver	            Yes	No	No   - maybe there is none, should return nothing if so (or the optimizer itself/solver variable)
function MOI.get(::Optimizer{T}, ::MOI.RawSolver) where {T}
    # return opt.qci_client
    return nothing
end

# Provider calls receive the typed silent setting and use the scoped capture in
# `qci_client_wrapper`, so client output is suppressed without redirecting
# unrelated output around the whole solve.
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

function MOI.get(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    MOI.supports(solver, attr) || throw(MOI.UnsupportedAttribute(attr))

    return solver.attributes[attr.name]
end

# DIRAC-3 parameter ranges follow QCI's provider guide:
# https://quantumcomputinginc.com/learn/module/introduction-to-dirac-3/dirac-3-developer-beginner-guide
function validate_raw_optimizer_attribute(name::String, value)
    if name == "num_samples"
        if value isa Bool || !(value isa Integer) || !(1 <= value <= 100)
            throw(
                ArgumentError(
                    "raw optimizer attribute 'num_samples' must be an integer in 1:100; " *
                    "received $(repr(value))",
                ),
            )
        end
    elseif name == "relaxation_schedule"
        if value isa Bool || !(value isa Integer) || !(1 <= value <= 4)
            throw(
                ArgumentError(
                    "raw optimizer attribute 'relaxation_schedule' must be an integer in 1:4; " *
                    "received $(repr(value))",
                ),
            )
        end
    elseif name == "sum_constraint"
        if !isnothing(value) &&
           (value isa Bool ||
            !(value isa Real) ||
            !isfinite(value) ||
            !(1 <= value <= 10_000))
            throw(
                ArgumentError(
                    "raw optimizer attribute 'sum_constraint' must be a finite real " *
                    "number in [1, 10000], or `nothing` to select the integer job; " *
                    "received $(repr(value))",
                ),
            )
        end
    elseif name == "job_name"
        value isa AbstractString || throw(
            ArgumentError(
                "raw optimizer attribute 'job_name' must be a string; " *
                "received $(repr(value))",
            ),
        )
        return String(value)
    elseif name == "job_tags"
        if !(value isa AbstractVector) || !all(tag -> tag isa AbstractString, value)
            throw(
                ArgumentError(
                    "raw optimizer attribute 'job_tags' must be a vector of strings; " *
                    "received $(repr(value))",
                ),
            )
        end
        return String[String(tag) for tag in value]
    end

    return value
end

function MOI.set(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute, value) where {T}
    MOI.supports(solver, attr) || throw(MOI.UnsupportedAttribute(attr))

    if attr.name == "device_type"
        # Treat this as a special case as this modifies the supported attributes
        MOI.set(solver, DeviceType(), value)
    else
        solver.attributes[attr.name] = validate_raw_optimizer_attribute(attr.name, value)
    end
end

function MOI.supports(solver::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    if attr.name ∈ QCI_GENERIC_ATTRIBUTES
        return true
    else
        device = QCIOpt.qci_device(T, MOI.get(solver, QCIOpt.DeviceType()))::QCI_DEVICE

        return qci_supports_attribute(device, attr.name)
    end
end

# [x] NumberOfThreads	    Yes	Yes	Yes  
MOI.supports(::Optimizer{T}, ::MOI.NumberOfThreads) where {T} = false # thread is not configurable by the user 

function MOI.get(solver::Optimizer{T}, ::QCIOpt.DeviceType) where {T}
    return solver.attributes["device_type"]
end

function MOI.set(solver::Optimizer{T}, ::QCIOpt.DeviceType, spec::AbstractString) where {T}
    qci_supports_device(spec) || throw(UnsupportedDevice(spec))

    solver.device = qci_device(T, spec)
    empty!(solver.attributes)
    merge!(solver.attributes, qci_default_attributes(solver.device))

    return nothing
end

MOI.supports(::Optimizer{T}, ::QCIOpt.DeviceType) where {T} = true
