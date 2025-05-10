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
    # TODO: Call QCI, store results

    return nothing
end

# If your solver accepts primal or dual warm-starts, implement:
# [ ]VariablePrimalStart
# [ ]ConstraintDualStart

# NOTE: Unsupported constraints at runtime
# In some cases, your solver may support a particular type of constraint (for example, quadratic constraints), but only if the data meets some condition (for example, it is convex).
# In this case, declare that you support the constraint, and throw AddConstraintNotAllowed.