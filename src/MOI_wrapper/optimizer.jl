# [ ] The Optimizer object

function default_settings()
    return Dict{String,Any}(
        "device_type" => "dirac-3",
        "api_token"   => QCI_TOKEN[],
    )
end

mutable struct Optimizer{T} <: MOI.AbstractOptimizer
    settings::Dict{String,Any}

    function Optimizer{T}() where {T}
        return new{T}(
            default_settings(),
        )
    end
end

Optimizer(args...; kwargs...) = Optimizer{Float64}(args...; kwargs...)

# [x] empty!
function MOI.empty!(solver::Optimizer{T}) where {T}
    # TODO: Erase all solver data

    return solver
end

# [x] is_empty
function MOI.is_empty(solver::Optimizer{T})::Bool where {T}
    # TODO: Check if solver is empty

    return true
end

# No incremental interface
MOI.supports_incremental_interface(::Optimizer{T}) where {T} = false

# [ ] Define optimize!(::ModelLike, ::ModelLike)
function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    api_token = MOI.get(solver, QCIOpt.APIToken())

    isnothing(api_token) || error("QCI API Token is not defined.")

    device = QCIOpt.qci_device(MOI.get(solver, QCIOpt.DeviceType()))::QCI_DEVICE

    QCIOpt.qci_optimize!(solver, model, device) # TODO: Call QCI

    # TODO: Store results

    return nothing
end

function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::QCI_DEVICE) where {T}
    return nothing
end

function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_1) where {T}

end

function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_2) where {T}

end

function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_3) where {T}

end


# If your solver accepts primal or dual warm-starts, implement:
# [ ]VariablePrimalStart
# [ ]ConstraintDualStart

# NOTE: Unsupported constraints at runtime
# In some cases, your solver may support a particular type of constraint (for example, quadratic constraints), but only if the data meets some condition (for example, it is convex).
# In this case, declare that you support the constraint, and throw AddConstraintNotAllowed.