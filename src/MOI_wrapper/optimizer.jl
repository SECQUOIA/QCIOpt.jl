@doc raw"""
    VarMap{S,T}
"""
struct VarMap{S,T}
    map::Dict{S,T}
    inv::Dict{T,S}
    idx::Dict{S,Int}

    function VarMap{S,T}(pairs) where {S,T}
        map = sizehint!(Dict{S,T}(), length(pairs))
        inv = sizehint!(Dict{T,S}(), length(pairs))
        idx = sizehint!(Dict{T,S}(), length(pairs))

        for (i, (s, t)) in enumerate(pairs)
            map[s] = t
            inv[t] = s
            idx[t] = i
        end

        return new{S,T}(map, inv, idx)
    end
end

source(vm::VarMap{S,T}) where {S,T}  = collect(S, values(vm.inv))
target(vm::VarMap{S,T}) where {S,T}  = collect(T, values(vm.map))
indices(vm::VarMap{S,T}) where {S,T} = collect(Int, values(vm.idx))

VarMap{S,T}() where {S,T} = VarMap{S,T}([])

Base.length(vm::VarMap{S,T}) where {S,T} = length(vm.map)

Base.isempty(vm::VarMap{S,T}) where {S,T} = isempty(vm.map) && isempty(vm.inv) && isempty(vm.idx)

function Base.empty!(vm::VarMap{S,T}) where {S,T}
    empty!(vm.map)
    empty!(vm.inv)
    empty!(vm.idx)

    return vm
end

function var_map!(vm::VarMap{S,T}, s::S, t::T) where {S,T}
    vm.map[s] = t
    vm.inv[t] = s
    vm.idx[s] = length(vm.map)

    return vm
end

var_map(vm::VarMap{S,T}, v::S) where {S,T} = vm.map[v]::T
var_inv(vm::VarMap{S,T}, v::T) where {S,T} = vm.inv[v]::S
var_idx(vm::VarMap{S,T}, v::S) where {S,T} = vm.idx[v]::Integer

# [ ] The Optimizer object

@doc raw"""
    Sample{U,T}

- point: Solution Vector
- value: Objective Function
- reads: Solution Multiplicity
"""
struct Sample{U,T}
    point::Vector{U}
    value::T
    reads::Int
end

@doc raw"""

"""
struct Solution{U,T}
    samples::Vector{Sample{U,T}}
    metadata::Dict{String,Any}
end

Solution{U,T}() where {U,T} = Solution{U,T}(Sample{U,T}[], Dict{String,Any}())

Base.isempty(solution::Solution{U,T}) where {U,T} = isempty(solution.samples) && isempty(solution.metadata)

function Base.empty!(solution::Solution{U,T}) where {U,T}
    empty!(solution.samples)
    empty!(solution.metadata)

    return solution
end

mutable struct Optimizer{T} <: MOI.AbstractOptimizer
    # Polynomial
    poly::Any
    qubo::Any

    # Variable Bounds
    lower::Dict{VI,T}
    upper::Dict{VI,T}
    fixed::Dict{VI,T}

    # Variable Mapping
    source_map::VarMap{VI,PolyVar}
    target_map::VarMap{PolyVar,Int}

    # Results
    solution::Solution{T,T}

    # Solver Settings
    attributes::Dict{String,Any}
    # qci_client::Union{QCI.OptimizationClient, Nothing}      # RawSolver attribute

    function Optimizer{T}() where {T}
        return new{T}(
            nothing,                           # poly
            nothing,                           # qubo
            Dict{VI,T}(),                      # lower
            Dict{VI,T}(),                      # upper
            Dict{VI,T}(),                      # fixed
            VarMap{VI,PolyVar}(),              # source_map
            VarMap{PolyVar,Int}(),             # target_map
            Solution{T,T}(),                   # solution
            qci_default_attributes("dirac-3"), # attributes
        )
    end
end

Optimizer(args...; kwargs...) = Optimizer{Float64}(args...; kwargs...)

# [x] empty!
function MOI.empty!(solver::Optimizer{T}) where {T}
    solver.poly = nothing
    solver.qubo = nothing

    empty!(solver.lower)
    empty!(solver.upper)
    empty!(solver.fixed)

    empty!(solver.source_map)
    empty!(solver.target_map)

    empty!(solver.solution)

    return solver
end

# [x] is_empty
function MOI.is_empty(solver::Optimizer{T})::Bool where {T}
    isnothing(solver.poly) || return false
    isnothing(solver.qubo) || return false

    isempty(solver.lower) || return false
    isempty(solver.upper) || return false
    isempty(solver.fixed) || return false
    
    isempty(solver.source_map) || return false
    isempty(solver.target_map) || return false
    
    isempty(solver.solution) || return false

    return true
end

# No incremental interface
MOI.supports_incremental_interface(::Optimizer{T}) where {T} = false

# [ ] Define optimize!(::ModelLike, ::ModelLike)
function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    api_token = MOI.get(solver, MOI.RawOptimizerAttribute("api_token"))

    isnothing(api_token) && error("QCI API Token is not defined.")

    device = QCIOpt.qci_device(MOI.get(solver, QCIOpt.DeviceType()))::QCI_DEVICE

    @assert MOI.get(model, MOI.ObjectiveSense()) === MOI.MIN_SENSE "$(device) only supports minimizing"

    QCIOpt.qci_optimize!(solver, model, device; api_token)

    return (MOIU.identity_index_map(model), false)
end

function qci_optimize! end

MOI.supports(::Optimizer{T}, ::MOI.ObjectiveFunction{F}) where {T,F<:Union{VI,SAF{T},SQF{T}}} = true

MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{S}) where {T,S<:Union{LT{T},EQ{T},GT{T},MOI.Interval{T}}} = true
MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{S}) where {T,S<:Union{MOI.ZeroOne,MOI.Integer}}           = true

function parse_polynomial(model::MOI.ModelLike, vm::VarMap)
    F = MOI.get(model, MOI.ObjectiveFunctionType())
    f = MOI.get(model, MOI.ObjectiveFunction{F}())

    return parse_polynomial(f, vm)
end

function parse_polynomial(v::VI, vm::VarMap{VI,PolyVar})
    p = PolyTerm{T}[var_map(vm, v)]

    return DP.polynomial(p)
end

function parse_polynomial(f::SAF{T}, vm::VarMap{VI,PolyVar}) where {T}
    p = sizehint!(PolyTerm{T}[f.constant], length(f.terms))

    for t in f.terms
        v = t.variable
        c = t.coefficient

        x = var_map(vm, v)

        push!(p, c * x)
    end

    return DP.polynomial(p)
end

function parse_polynomial(f::SQF{T}, vm::VarMap{VI,PolyVar}) where {T}
    p = sizehint!(PolyTerm{T}[f.constant], length(f.affine_terms) + length(f.quadratic_terms))

    for t in f.affine_terms
        v = t.variable
        c = t.coefficient

        x = var_map(vm, v)

        push!(p, c * x)
    end

    for t in f.quadratic_terms
        v_1 = t.variable_1
        v_2 = t.variable_2
        c   = t.coefficient

        x_1 = var_map(vm, v_1)
        x_2 = var_map(vm, v_2)

        if v_1 == v_2
            push!(p, (c/2) * (x_1 * x_2))
        else
            push!(p, c * (x_1 * x_2))
        end
    end

    return DP.polynomial(p)
end

function parse_qubo_matrix(f::SQF{T}, vm::VarMap{VI,PolyVar}) where {T}
    n = length(vm)
    Q = zeros(T, n, n)

    for t in f.affine_terms
        v = t.variable
        c = t.coefficient
        i = var_idx(vm, v)

        Q[i, i] += c
    end

    for t in f.quadratic_terms
        v_1 = t.variable_1
        v_2 = t.variable_2
        c   = t.coefficient
        i_1 = var_idx(vm, v_1)
        i_2 = var_idx(vm, v_2)

        if i_1 == i_2
            Q[i_1, i_2] += (c/2)
        else
            Q[i_1, i_2] += c
        end
    end

    return (Symmetric((Q + Q') / 2), f.constant)
end

function parse_polynomial(f::F, vm::VarMap{VI,PolyVar}) where {F<:MOI.AbstractFunction}
    # TODO: Interpret Nonlinear function
    error("Nonlinear Functions are still not supported.")

    return nothing
end

@doc raw"""
    retrieve_variable_bounds!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}

Retrieve variable bounds from the model and store them in the solver. 
- vi: variable index
- li: lower bound
- ui: upper bound
- fi: fixed value
- ci: constraint index
"""
function retrieve_variable_bounds!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI, MOI.ZeroOne}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)

        if haskey(solver.lower, vi)
            solver.lower[vi] = max(solver.lower[vi], zero(T))
        else
            solver.lower[vi] = zero(T)
        end

        if haskey(solver.upper, vi)
            solver.upper[vi] = max(solver.upper[vi], one(T))
        else
            solver.upper[vi] = one(T)
        end
    end

    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI, GT{T}}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)
        li = MOI.get(model, MOI.ConstraintSet(), ci).lower

        if haskey(solver.lower, vi)
            solver.lower[vi] = max(solver.lower[vi], li)
        else
            solver.lower[vi] = li
        end
    end

    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI, LT{T}}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)
        ui = MOI.get(model, MOI.ConstraintSet(), ci).upper

        if haskey(solver.upper, vi)
            solver.upper[vi] = max(solver.upper[vi], ui)
        else
            solver.upper[vi] = ui
        end
    end

    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI, MOI.Interval{T}}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)
        li = MOI.get(model, MOI.ConstraintSet(), ci).lower
        ui = MOI.get(model, MOI.ConstraintSet(), ci).upper
      
        if li == ui 
            solver.fixed[vi] = li
        end

        if haskey(solver.lower, vi)
            solver.lower[vi] = max(solver.lower[vi], li)
        else
            solver.lower[vi] = li
        end

        if haskey(solver.upper, vi)
            solver.upper[vi] = max(solver.upper[vi], ui)
        else
            solver.upper[vi] = ui
        end
    end

    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI, EQ{T}}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)
        fi = MOI.get(model, MOI.ConstraintSet(), ci).value

        solver.fixed[vi] = fi
    end
end

function get_fix(solver::Optimizer{T}) where {T}
    return Pair{PolyVar,T}[var_map(solver.source_map, vi) => ci for (vi, ci) in solver.fixed]
end

function fix_variables(Q::AbstractMatrix{T}, fix) where {T}
    if isempty(fix)
        return (Q, zero(T))
    else
        error("Can't fix variables for QUBO problems.")
    end
end

function fix_variables(p::Poly{T}, fix)::Poly{T} where {T}
    if isempty(fix)
        return p
    else
        return DP.subs(p, first.(fix) => last.(fix))
    end
end

function get_levels(solver::Optimizer{T}, num_vars::Integer) where {T}
    return map(
        i -> let vi = var_inv(solver.source_map, var_inv(solver.target_map, i))
            (floor(Int, solver.upper[vi]) - ceil(Int, solver.lower[vi])) + 1
        end,
        1:num_vars,
    )
end

function rescale_variables(p::Poly{T}, vars::AbstractVector{PolyVar}, l::AbstractVector{T}, u::AbstractVector{T}) where {T}
    # NOTE: This only works for the integer case!
    subs = [xi => (xi - li) for (xi, li, ui) in zip(vars, l, u) if !iszero(l)]

    if isempty(subs)
        return p
    else
        return DP.subs(p, first.(subs) => last.(subs))
    end
end

@doc raw"""
    readjust_poly_values(solver::Optimizer{T}, n::Integer, samples::Vector{Sample{T,T}}) where {T}    
"""
function readjust_poly_values(solver::Optimizer{T}, n::Integer, samples::Vector{Sample{T,T}}, sense) where {T}
    @assert solver.poly isa DP.AbstractPolynomial{T}

    adjusted_samples = sizehint!(Sample{T,T}[], length(samples))

    for sample in samples
        point = Vector{T}(undef, n)
        x     = Vector{PolyVar}(undef, n)

        for i = 1:n
            xi = var_inv(solver.target_map, i)
            vi = var_inv(solver.source_map, xi)

            if haskey(solver.fixed, vi)
                point[i] = solver.fixed[vi]
                x[i]     = xi

                continue
            end

            li = solver.lower[vi]

            point[i] = sample.point[i] + li
            x[i]     = xi
        end

        value = if sense === MOI.MAX_SENSE
            -solver.poly(x => point)
        else # MOI.MIN_SENSE || MOI.FEASIBILITY_SENSE
            solver.poly(x => point)
        end

        push!(adjusted_samples, Sample{T,T}(point, value, sample.reads))
    end

    return sort!(adjusted_samples; by = s -> (s.value, -s.reads))
end

@doc raw"""
    readjust_qubo_values(solver::Optimizer{T}, n::Integer, samples::Vector{Sample{T,T}}) where {T}    
"""
function readjust_qubo_values(solver::Optimizer{T}, n::Integer, samples::Vector{Sample{T,T}}, sense) where {T}
    @assert solver.qubo isa Tuple

    adjusted_samples = sizehint!(Sample{T,T}[], length(samples))

    for sample in samples
        point = Vector{T}(undef, n)
        x     = Vector{PolyVar}(undef, n)

        for i = 1:n
            xi = var_inv(solver.target_map, i)
            vi = var_inv(solver.source_map, xi)

            if haskey(solver.fixed, vi)
                point[i] = solver.fixed[vi]
                x[i]     = xi

                continue
            end

            li = solver.lower[vi]

            point[i] = sample.point[i] + li
            x[i]     = xi
        end

        Q, c = solver.qubo

        value = if sense === MOI.MAX_SENSE
            -(point' * Q * point + c)
        else # MOI.MIN_SENSE || MOI.FEASIBILITY_SENSE
            (point' * Q * point + c)
        end

        push!(adjusted_samples, Sample{T,T}(point, value, sample.reads))
    end

    return sort!(adjusted_samples; by = s -> (s.value, -s.reads))
end

function copy_model_attributes!(solver, model)
    for attr in MOI.get(model, MOI.ListOfModelAttributesSet())
        attr isa MOI.ObjectiveSense        && continue
        attr isa MOI.ObjectiveFunction     && continue
        # attr isa MOI.ObjectiveFunctionType && continue

        MOI.set(solver, attr, MOI.get(model, attr))
    end

    for attr in MOI.get(model, MOI.ListOfOptimizerAttributesSet())
        MOI.set(solver, attr, MOI.get(model, attr))
    end

    return nothing
end


# If your solver accepts primal or dual warm-starts, implement:
# [ ]VariablePrimalStart
# [ ]ConstraintDualStart

# NOTE: Unsupported constraints at runtime
# In some cases, your solver may support a particular type of constraint (for example, quadratic constraints), but only if the data meets some condition (for example, it is convex).
# In this case, declare that you support the constraint, and throw AddConstraintNotAllowed.