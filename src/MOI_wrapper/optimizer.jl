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

mutable struct Optimizer{T} <: MOI.AbstractOptimizer
    # Variable Bounds
    upper::Dict{VI,T}
    lower::Dict{VI,T}

    # Variable Mapping
    source_map::VarMap{VI,DP.Variable}
    target_map::VarMap{DP.Variable,Int}

    # Solver Settings
    settings::Dict{String,Any}

    function Optimizer{T}() where {T}
        return new{T}(
            Dict{VI,T}(),              # upper
            Dict{VI,T}(),              # lower
            VarMap{VI,DP.Variable}(),  # source_map
            VarMap{DP.Variable,Int}(), # target_map
            default_settings(),        # settings
        )
    end
end

Optimizer(args...; kwargs...) = Optimizer{Float64}(args...; kwargs...)

# [x] empty!
function MOI.empty!(solver::Optimizer{T}) where {T}
    # TODO: Erase all model data (besides solver settings, keep those)
    empty!(solver.upper)
    empty!(solver.lower)

    empty!(solver.source_map)
    empty!(solver.target_map)

    return solver
end

# [x] is_empty
function MOI.is_empty(solver::Optimizer{T})::Bool where {T}
    # TODO: Check if solver is empty
    isempty(solver.upper) || return false
    isempty(solver.lower) || return false

    isempty(solver.source_map) || return false
    isempty(solver.target_map) || return false

    return true
end

# No incremental interface
MOI.supports_incremental_interface(::Optimizer{T}) where {T} = false

# [ ] Define optimize!(::ModelLike, ::ModelLike)
function MOI.optimize!(solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    api_token = MOI.get(solver, QCIOpt.APIToken())

    isnothing(api_token) && error("QCI API Token is not defined.")

    device = QCIOpt.qci_device(MOI.get(solver, QCIOpt.DeviceType()))::QCI_DEVICE

    QCIOpt.qci_optimize!(solver, model, device; api_token) # TODO: Call QCI

    # TODO: Store results

    return nothing
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
    p = DP.polynomial(_ -> zero(T), target(vm))

    return p + var_map(vm, v)
end

function parse_polynomial(f::SAF{T}, vm::VarMap{VI,PV}) where {T}
    p = DP.polynomial(_ -> zero(T), target(vm))

    for t in f.terms
        v = t.variable
        c = t.coefficient

        x = var_map(vm, v)

        p += c * x
    end

    return p + f.constant
end

function parse_polynomial(f::SQF{T}, vm::VarMap{VI,PV}) where {T}
    p = DP.polynomial(_ -> zero(T), target(vm))

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

function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, ::DIRAC_3; api_token::AbstractString) where {T}
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

    poly = parse_polynomial(model, solver.source_map)

    file     = qci_data_file(x -> var_map(solver.target_map, x), poly)
    file_id  = qci_upload_file(file; api_token)
    job_body = qci_build_job_body(file_id; api_token) # TODO: Pass Parameters for this
    response = qci_process_job(job_body; api_token)
    samples  = qci_get_results(response)

    sort!(samples; by = sample -> sample.v)

    # TODO: Store results

    return nothing
end


# If your solver accepts primal or dual warm-starts, implement:
# [ ]VariablePrimalStart
# [ ]ConstraintDualStart

# NOTE: Unsupported constraints at runtime
# In some cases, your solver may support a particular type of constraint (for example, quadratic constraints), but only if the data meets some condition (for example, it is convex).
# In this case, declare that you support the constraint, and throw AddConstraintNotAllowed.