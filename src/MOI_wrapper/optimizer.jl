@doc raw"""
    VarMap{S,T}
"""
struct VarMap{S,T}
    map::Dict{S,T}
    inv::Dict{T,S}

    function VarMap{S,T}(pairs) where {S,T}
        map = Dict{S,T}(s => t for (s, t) in pairs)
        inv = Dict{T,S}(t => s for (s, t) in pairs)

        return new{S,T}(
            map,
            inv,
        )
    end
end

source(vm::VarMap{S,T}) where {S,T} = collect(S, values(vm.inv))
target(vm::VarMap{S,T}) where {S,T} = collect(T, values(vm.map))

VarMap{S,T}() where {S,T} = VarMap{S,T}([])

Base.isempty(vm::VarMap{S,T}) where {S,T} = isempty(vm.map) && isempty(vm.inv)

function Base.empty!(vm::VarMap{S,T}) where {S,T}
    empty!(vm.map)
    empty!(vm.inv)

    return vm
end

function var_map!(vm::VarMap{S,T}, s::S, t::T) where {S,T}
    vm.map[s] = t
    vm.inv[t] = s

    return vm
end

var_map(vm::VarMap{S,T}, v::S) where {S,T} = vm.map[v]::T
var_inv(vm::VarMap{S,T}, v::T) where {S,T} = vm.inv[v]::S

# [ ] The Optimizer object
function default_settings()
    return Dict{String,Any}(
        "device_type" => "dirac-3",
        "api_token"   => QCI_TOKEN[],
    )
end

@doc raw"""
    Sample{U,T}

- x: Solution Vector
- v: Objective Function
- r: Solution Multiplicity
"""
struct Sample{U,T}
    x::Vector{U}
    v::T
    r::Int
end

@doc raw"""

"""
struct Solution{U,T}
    samples::Vector{Sample{U,T}}
    metadata::Any
end

mutable struct Optimizer{T} <: MOI.AbstractOptimizer
    # Variable Bounds
    lower::Dict{VI,T}
    upper::Dict{VI,T}
    fixed::Dict{VI,T}

    # Variable Mapping
    source_map::VarMap{VI,DP.Variable}
    target_map::VarMap{DP.Variable,Int}

    # Results
    samples::Vector{Sample{T,T}}

    # Solver Settings
    settings::Dict{String,Any}
    # qci_client::Union{QCI.OptimizationClient, Nothing}      # RawSolver attribute

    function Optimizer{T}() where {T}
        return new{T}(
            Dict{VI,T}(),              # lower
            Dict{VI,T}(),              # upper
            Dict{VI,T}(),              # fixed
            VarMap{VI,DP.Variable}(),  # source_map
            VarMap{DP.Variable,Int}(), # target_map
            Sample{T,T}[],           # samples
            default_settings(),        # settings
        )
    end
end

Optimizer(args...; kwargs...) = Optimizer{Float64}(args...; kwargs...)

# [x] empty!
function MOI.empty!(solver::Optimizer{T}) where {T}
    # TODO: Erase all model data (besides solver settings, keep those)
    empty!(solver.lower)
    empty!(solver.upper)
    empty!(solver.fixed)

    empty!(solver.source_map)
    empty!(solver.target_map)

    empty!(solver.samples)

    return solver
end

# [x] is_empty
function MOI.is_empty(solver::Optimizer{T})::Bool where {T}
    # TODO: Check if solver is empty
    isempty(solver.lower) || return false
    isempty(solver.upper) || return false
    isempty(solver.fixed) || return false
    
    isempty(solver.source_map) || return false
    isempty(solver.target_map) || return false
    
    isempty(solver.samples) || return false

    return true
end

# No incremental interface
MOI.supports_incremental_interface(::Optimizer{T}) where {T} = false

# [ ] Define optimize!(::ModelLike, ::ModelLike)
function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    api_token = MOI.get(solver, QCIOpt.APIToken())

    isnothing(api_token) && error("QCI API Token is not defined.")

    device = QCIOpt.qci_device(MOI.get(solver, QCIOpt.DeviceType()))::QCI_DEVICE

    @assert MOI.get(model, MOI.ObjectiveSense()) === MOI.MIN_SENSE "$(device) only supports minimizing"

    QCIOpt.qci_optimize!(solver, model, device; api_token) # TODO: Call QCI

    # TODO: Store results

    return (MOIU.identity_index_map(model), false)
end

# function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::QCI_DEVICE) where {T}
    
# end

# function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_1) where {T}

# end

# function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_2) where {T}

# end

MOI.supports(::Optimizer{T}, ::MOI.ObjectiveFunction{F}) where {T,F<:Union{VI,SAF{T},SQF{T}}} = true

MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{S}) where {T,S<:Union{LT{T},EQ{T},GT{T},MOI.Interval{T}}} = true
MOI.supports_constraint(::Optimizer{T}, ::Type{VI}, ::Type{S}) where {T,S<:Union{MOI.ZeroOne,MOI.Integer}}           = true

function parse_polynomial(model::MOI.ModelLike, vm::VarMap)
    F = MOI.get(model, MOI.ObjectiveFunctionType())
    f = MOI.get(model, MOI.ObjectiveFunction{F}())

    return parse_polynomial(f, vm)
end

function parse_polynomial(v::VI, vm::VarMap{VI,PV})
    p = DP.polynomial(_ -> zero(T), target(vm)) # zero of polynomial type with variables as in the model

    return p + var_map(vm, v)
end

function parse_polynomial(f::SAF{T}, vm::VarMap{VI,PV}) where {T}
    p = DP.polynomial(_ -> zero(T), target(vm)) # zero of polynomial type with variables as in the model

    for t in f.terms
        v = t.variable
        c = t.coefficient

        x = var_map(vm, v)

        p += c * x
    end

    return p + f.constant
end

function parse_polynomial(f::SQF{T}, vm::VarMap{VI,PV}) where {T}
    p = DP.polynomial(_ -> zero(T), target(vm)) # zero of polynomial type with variables as in the model

    for t in f.affine_terms
        v = t.variable
        c = t.coefficient

        x = var_map(vm, v)

        p += c * x
    end

    for t in f.quadratic_terms
        v_1 = t.variable_1
        v_2 = t.variable_2
        c   = t.coefficient

        x_1 = var_map(vm, v_1)
        x_2 = var_map(vm, v_2)

        if v_1 == v_2
            p += (c/2) * (x_1 * x_2)
        else
            p += c * (x_1 * x_2)
        end
    end

    return p + f.constant
end

function parse_polynomial(f::F, vm::VarMap{VI,PV}) where {F<:MOI.AbstractFunction}
    p = DP.polynomial(_ -> zero(T), target(vm)) # zero of polynomial type with variables as in the model

    # TODO: Interpret Nonlinear function
    error()

    return p
end

@doc raw"""
    retrieve_variable_bounds!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}

    
"""
function retrieve_variable_bounds!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
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

@doc raw"""
    get_substitutions_and_levels(solver::Optimizer{T}) where {T}
    
"""
function get_substitutions_and_levels(solver::Optimizer{T}) where {T}
    # NOTE: This only works for the integer case!

    subs = []
    lvls = Dict{Int,Int}()
    vars = Set{VI}(source(solver.source_map))

    # Fix Variables
    for (vi, fi) in solver.fixed
        xi = var_map(solver.source_map, vi)

        push!(subs, xi => fi)

        delete!(vars, vi)
    end

    # Rescale Remaining Variables
    for vi in vars
        xi = var_map(solver.source_map, vi)
        yi = var_map(solver.target_map, xi)

        li = convert(Int, solver.lower[vi])
        ui = convert(Int, solver.upper[vi])

        push!(subs, xi => xi - li)
        push!(lvls, yi => ui - li)
    end

    subs = first.(subs) => last.(subs)

    return (subs, lvls)
end

qci_max_level(::DIRAC_3) = 954

@doc raw"""
    readjust_variable_values(solver::Optimizer{T}, n::Integer, samples::Vector{Sample{T,T}}) where {T}

"""
function readjust_variable_values(solver::Optimizer{T}, n::Integer, samples::Vector{Sample{T,T}}) where {T}
    adjusted_samples = sizehint!(Sample{T,T}[], length(samples))

    for sample in samples
        x = Vector{T}(undef, n)

        for i = 1:n
            yi = var_inv(solver.target_map, i)
            vi = var_inv(solver.source_map, yi)

            if haskey(solver.fixed, vi)
                x[i] = solver.fixed[vi]

                continue
            end

            li = solver.lower[vi]

            x[i] = sample.x[i] + li
        end

        push!(adjusted_samples, Sample{T,T}(x, sample.v, sample.r))
    end

    return sort!(adjusted_samples; by = s -> s.v)
end

@doc raw"""
    qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_3; api_token::AbstractString) where {T}

    
"""
function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_3; api_token::AbstractString) where {T}
    n = MOI.get(model, MOI.NumberOfVariables())

    DP.@polyvar(x[1:n])

    for (i, vi) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
        var_map!(solver.source_map, vi, x[i])
    end

    for i = 1:n
        var_map!(solver.target_map, x[i], i)
    end

    # TODO: Adjust variable bounds
    # (see `DynamicPolynomials.subs` @ https://juliaalgebra.github.io/MultivariatePolynomials.jl/stable/substitution/)
    # This has to return:
    # 1. A new, modified polynomial such that each original variable xᵢ ∈ [l, u] becomes xᵢ ∈ [0, u - l] under 
    #    the substitution rule xᵢ ↦ (xᵢ - l) for the integer case and xᵢ ↦ (xᵢ - l) / (u - l) for the real case
    #    where xᵢ ∈ [0, 1] (to be rescaled later according to variable precision)
    # 2. The new variable bounds, to be passed as qci_build_job_body(...; ..., num_levels = variable_bounds::Vector{Int})
    # 3. MAYBE: `undo(p)` function for undoing item 1.
    retrieve_variable_bounds!(solver, model)

    poly = parse_polynomial(model, solver.source_map)
    subs, lvls = get_substitutions_and_levels(solver)
    poly = DP.subs(poly, subs)

    num_levels = [haskey(lvls, i) ? lvls[i] : 0 for i = 1:n]

    @assert sum(num_levels) <= qci_max_level(device)

    file     = qci_data_file(x -> var_map(solver.target_map, x), poly)
    file_id  = qci_upload_file(file; api_token)
    job_body = qci_build_job_body(file_id; api_token, num_levels) # TODO: Pass Parameters for this
    response = qci_process_job(job_body; api_token)
    solution = qci_get_results(T, T, response)

    # Store results
    # TODO: Store solution metadata (QCI provides a lot of details about it!)
    append!(solver.samples, readjust_variable_values(solver, n, solution.samples))

    return nothing
end


# If your solver accepts primal or dual warm-starts, implement:
# [ ]VariablePrimalStart
# [ ]ConstraintDualStart

# NOTE: Unsupported constraints at runtime
# In some cases, your solver may support a particular type of constraint (for example, quadratic constraints), but only if the data meets some condition (for example, it is convex).
# In this case, declare that you support the constraint, and throw AddConstraintNotAllowed.