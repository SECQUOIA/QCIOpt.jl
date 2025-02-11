struct Variables{T}
    index::Vector{VI}
    lower::Vector{Union{T,Nothing}}
    upper::Vector{Union{T,Nothing}}
end

Base.length(var::Variables{T}) where {T} = length(var.index)

MOI.is_empty(var::Variables{T}) where {T} = isempty(var.index)

function set_bounds!(var::Variables{T}, vi::VI; lower = nothing, upper = nothing) where {T}
    !isnothing(lower) && var.lower[vi.index] = lower
    !isnothing(upper) && var.upper[vi.index] = upper

    return nothing
end
    

function MOI.add_variable(var::Variables{T}) where {T}
    vi = VI(length(var.index) + 1)

    push!(var.index, vi)
    push!(var.lower, nothing)
    push!(var.upper, nothing)

    return vi
end

struct Objective{T}
    sense::MOI.OptimizationSense
    func::SQF{T}
end

MOI.is_empty(obj::Objective{T}) where {T} = MOI.is_empty(obj.func)

struct Optimizer{T} <: MOI.AbstractOptimzer
    variables::Vector{VI}
    objective::Objective{T}
end

function MOI.is_empty(opt::Optimizer{T})::Bool where {T}
    return isempty(opt.objective) && isempty(opt.variables)
end
