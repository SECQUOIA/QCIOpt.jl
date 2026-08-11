@doc raw"""
    DIRAC_3 <: QCI_DIRAC <: QCI_DEVICE

## About

DIRAC-3 samples polynomial models. The device stores a variable map, a parsed
polynomial objective, and per-job configuration before submitting the job through
the QCI client.
"""
mutable struct DIRAC_3{T} <: QCI_DIRAC
    varmap::VarMap{VI,PolyVar}
    poly::Maybe{Poly{T}}
    config::Dict{String,Any}

    function DIRAC_3{T}() where {T}
        return new{T}(VarMap{VI,PolyVar}(), nothing, Dict{String,Any}())
    end
end

function Base.isempty(device::DIRAC_3{T}) where {T}
    return isempty(device.varmap) && isnothing(device.poly)
end

function Base.empty!(device::DIRAC_3{T}) where {T}
    empty!(device.varmap)
    device.poly = nothing

    return device
end

function qci_config(device::DIRAC_3{T}, attr::AbstractString) where {T}
    @assert qci_supports_attribute(device, attr)

    return device.config[attr]
end

function qci_config!(device::DIRAC_3{T}, attr::AbstractString, val::Any) where {T}
    @assert qci_supports_attribute(device, attr)

    device.config[attr] = val

    return nothing
end

QCI_DEVICES["dirac-3"] = DIRAC_3

const DIRAC_3_ATTRIBUTES = Set{String}([
    "num_samples",
    "relaxation_schedule",
])

qci_default_attributes(::Type{DIRAC_3{T}}) where {T} = Dict{String,Any}(
    qci_default_attributes()...,
    "device_type"         => "dirac-3",
    "num_samples"         => 10,
    "relaxation_schedule" => 1,
)

qci_supports_attribute(::DIRAC_3, attr::AbstractString) = attr ∈ DIRAC_3_ATTRIBUTES

qci_supports_objective(::DIRAC_3{T}, ::Type{VI}) where {T} = true
qci_supports_objective(::DIRAC_3{T}, ::Type{SAF{T}}) where {T} = true
qci_supports_objective(::DIRAC_3{T}, ::Type{SQF{T}}) where {T} = true

function qci_supports_constraint(
    ::DIRAC_3{T},
    ::Type{VI},
    ::Type{S},
) where {T,S<:Union{LT{T},EQ{T},GT{T},MOI.Interval{T},MOI.ZeroOne,MOI.Integer}}
    return true
end

@doc raw"""
    qci_load!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike) where {T}

Load the model into the device without touching the network: build the
variable map, retrieve variable bounds, copy model attributes, and parse the
objective polynomial. The device natively minimizes, so for `MAX_SENSE` models
the negated polynomial is stored and submitted; original objective values are
restored in [`readjust_poly_values`](@ref).

Returns the vector of `DynamicPolynomials` variables in model variable order.
The variable domains are validated later, by [`variable_domains`](@ref), which
`qci_optimize!` calls before any network access.
"""
function qci_load!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike) where {T}
    n = MOI.get(model, MOI.NumberOfVariables())

    DP.@polyvar(x[1:n])

    for (i, vi) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
        var_map!(device.varmap, vi, x[i])
    end

    # Bounds and integrality feed the transformation contract implemented by
    # `variable_domains`, `rescale_variables`, `get_levels`, and
    # `readjust_poly_values`.
    retrieve_variable_bounds!(solver, model)

    copy_model_attributes!(solver, model)

    device.poly = let p = parse_polynomial(model, device.varmap)
        if MOI.get(model, MOI.ObjectiveSense()) === MOI.MAX_SENSE
            -p
        else
            p
        end
    end

    return x
end

@doc raw"""
    qci_build_poly_job_body(solver::Optimizer, device::DIRAC_3, file_id, num_levels; api_token, silent)

Build a DIRAC-3 integer-polynomial job body from the validated raw optimizer
attributes stored on `solver`. This is the network-free caller-to-client
boundary used by `qci_optimize!`.
"""
function qci_build_poly_job_body(
    solver::Optimizer{T},
    ::DIRAC_3{T},
    file_id::AbstractString,
    num_levels::AbstractVector{<:Integer};
    api_token::AbstractString = qci_default_token(),
    silent::Bool = false,
) where {T}
    return qci_build_poly_job_body(
        file_id;
        api_token,
        silent,
        device_type = "dirac-3",
        job_type = "sample-hamiltonian-integer",
        num_levels,
        num_samples = MOI.get(solver, MOI.RawOptimizerAttribute("num_samples")),
        relaxation_schedule = MOI.get(
            solver,
            MOI.RawOptimizerAttribute("relaxation_schedule"),
        ),
        job_name = MOI.get(solver, MOI.RawOptimizerAttribute("job_name")),
        job_tags = MOI.get(solver, MOI.RawOptimizerAttribute("job_tags")),
    )
end

@doc raw"""
    qci_optimize!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}

Submit the loaded model to the DIRAC-3 device and store the parsed results.
"""
function qci_optimize!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}
    x = qci_load!(solver, device, model)

    silent              = MOI.get(solver, MOI.Silent())
    file_name           = MOI.get(solver, MOI.RawOptimizerAttribute("file_name"))
    # Build (and validate) first: `qci_build_poly_request` is network-free, while
    # `qci_max_level` reads the allocation over the network. An unusable domain
    # must report itself as such, not as a missing-credentials error.
    request = qci_build_poly_request(solver, device, x; file_name)

    assert_level_budget(request.num_levels, qci_max_level(device; api_token, silent))

    file_id  = qci_upload_file(request.file; api_token, silent)
    job_body = qci_build_poly_job_body(
        solver,
        device,
        file_id,
        request.num_levels;
        api_token,
        silent,
    )
    response = qci_process_job(job_body; api_token, silent)
    solution = qci_parse_results(T, T, response)

    qci_store_results!(solver, device, model, x, solution)

    return nothing
end

@doc raw"""
    qci_store_results!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike, vars, solution::Solution{T,T}) where {T}

Store a parsed provider solution on the solver, reading the model's
`MOI.ObjectiveSense` to restore original objective values and best-first
ordering. Network-free, so the sense handoff is testable offline.
"""
function qci_store_results!(
    solver::Optimizer{T},
    device::DIRAC_3{T},
    model::MOI.ModelLike,
    vars,
    solution::Solution{T,T},
) where {T}
    # TODO: Preserve job identifiers, timing, status, and provider diagnostics in metadata.
    solver.solution = Solution{T,T}(
        readjust_poly_values(solver, device, vars, solution.samples, MOI.get(model, MOI.ObjectiveSense())),
        solution.metadata,
    )

    return nothing
end

@doc raw"""
    qci_max_level(::DIRAC_3; url = QCI_URL, api_token = qci_default_token(), silent = false)

Return the DIRAC-3 total-level budget for the configured allocation: `500` on
the free tier and `949` on the paid tier. Set `silent = true` to suppress
provider console output while reading the allocation.
"""
function qci_max_level(
    ::DIRAC_3;
    url::AbstractString = QCI_URL,
    api_token::Maybe{AbstractString} = qci_default_token(),
    silent::Bool = false,
)
    return qci_is_free_tier(; url, api_token, silent) ? 500 : 949
end

@doc raw"""
    qci_build_poly_request(solver::Optimizer{T}, device::DIRAC_3{T}, vars; file_name = nothing) where {T}

Build everything a DIRAC-3 submission needs from a loaded model, without
touching the network: the shifted polynomial, the polynomial file body, and the
per-variable level counts. This is the whole transformation half of
`qci_optimize!`, split out so it can be exercised offline.

Applies the contract documented on [`variable_domains`](@ref), and so raises that
function's domain errors. Being network-free is what lets an unusable model fail
with its own error rather than with a credentials or connectivity error; the
level budget is checked separately by [`assert_level_budget`](@ref), because the
allocation limit itself has to be read from the provider.

Returns a named tuple `(; poly, file, num_levels)`.
"""
function qci_build_poly_request(
    solver::Optimizer{T},
    device::DIRAC_3{T},
    vars;
    file_name::Union{AbstractString,Nothing} = nothing,
) where {T}
    domains    = variable_domains(solver, device, vars)
    num_levels = get_levels(domains)

    poly = rescale_variables(device.poly, vars, T[li for (li, _) in domains])
    file = qci_data_file(xi -> var_idx(device.varmap, var_inv(device.varmap, xi)), poly; file_name)

    return (; poly, file, num_levels)
end

@doc raw"""
    variable_domains(solver::Optimizer{T}, device::DIRAC_3{T}, vars) where {T}

Return the integer domain `(lᵢ, uᵢ)` that DIRAC-3 samples for each variable in
`vars`, in the order given, validating the model against what the device can
represent.

DIRAC-3 receives `sample-hamiltonian-integer` jobs, whose variable `i` takes
the `num_levelsᵢ` consecutive integer values `0, 1, …, num_levelsᵢ - 1`. The
transformation contract is therefore:

1. every variable is integer-valued and box-bounded, so its domain is the
   integer interval `[lᵢ, uᵢ] = [ceil(lowerᵢ), floor(upperᵢ)]`;
2. the objective is submitted after the substitution `xᵢ ↦ xᵢ + lᵢ`
   ([`rescale_variables`](@ref)), which moves that domain onto `[0, uᵢ - lᵢ]`;
3. the device is told `num_levelsᵢ = uᵢ - lᵢ + 1` ([`get_levels`](@ref));
4. a returned point `yᵢ` maps back as `xᵢ = yᵢ + lᵢ`
   ([`readjust_poly_values`](@ref)), inverting step 2.

Steps 2 and 4 must use the same `lᵢ` computed here, which is why each step
derives its bounds from this function rather than from `solver.lower` directly:
for an `Int` variable declared over fractional bounds the sampled lattice starts
at `ceil(lowerᵢ)`, not at `lowerᵢ`.

Throws an `ErrorException` naming the offending variable when a domain is
unbounded, infinite, free of integer points, continuous, or wider than the
machine integer range can count.
"""
function variable_domains(solver::Optimizer{T}, device::DIRAC_3{T}, vars) where {T}
    return map(xi -> variable_domain(solver, device, xi), vars)
end

function variable_domain(solver::Optimizer{T}, device::DIRAC_3{T}, xi::PolyVar) where {T}
    vi = var_inv(device.varmap, xi)

    if !haskey(solver.lower, vi) || !haskey(solver.upper, vi)
        error(
            "DIRAC-3 requires a finite lower and upper bound on every variable, but " *
            "variable index $(vi.value) is missing " *
            (haskey(solver.lower, vi) ? "an upper" : "a lower") *
            " bound. Bound it, e.g. `@variable(model, l <= x <= u, Int)`.",
        )
    end

    lo = solver.lower[vi]
    up = solver.upper[vi]

    if !isfinite(lo) || !isfinite(up)
        error(
            "DIRAC-3 requires a finite lower and upper bound on every variable, but " *
            "variable index $(vi.value) is bounded by [$(lo), $(up)]. " *
            "Bound it, e.g. `@variable(model, l <= x <= u, Int)`.",
        )
    end

    # A variable pinned by `MOI.EqualTo` spans a single level, so it is
    # representable whether or not the model also declares it integral.
    if !(vi in solver.integral) && !haskey(solver.fixed, vi)
        error(
            "DIRAC-3 samples integer-valued variables only, but variable index " *
            "$(vi.value) is continuous. Declare it as `Int` or `Bin`, or fix it to a " *
            "single value. Continuous DIRAC-3 jobs use the `sample-hamiltonian` job " *
            "type, whose simplex `sum_constraint` domain is not expressible as " *
            "variable bounds, and QCIOpt does not submit it.",
        )
    end

    # Widen before rounding: `ceil(Int, ...)` throws `InexactError` on bounds
    # past the machine integer range, and the level count below can exceed that
    # range even when both bounds fit inside it.
    li = ceil(BigInt, lo)
    ui = floor(BigInt, up)

    if li > ui
        error(
            "DIRAC-3 requires a nonempty integer domain, but variable index " *
            "$(vi.value) is bounded by [$(lo), $(up)], which contains no integer point.",
        )
    end

    if li < typemin(Int) || ui > typemax(Int) || (ui - li + 1) > typemax(Int)
        error(
            "DIRAC-3 cannot represent the domain of variable index $(vi.value): " *
            "[$(lo), $(up)] covers $(ui - li + 1) integer points between $(li) and " *
            "$(ui), which does not fit in the machine integer range. A job allocates " *
            "one level per integer point, and the allocation budget is a few hundred, " *
            "so tighten the bounds.",
        )
    end

    return (Int(li), Int(ui))
end

@doc raw"""
    get_levels(domains::AbstractVector{Tuple{Int,Int}})
    get_levels(solver::Optimizer{T}, device::DIRAC_3{T}, vars) where {T}

Number of levels DIRAC-3 allocates per variable: one per integer point of the
transformed domain `[0, uᵢ - lᵢ]`. See [`variable_domains`](@ref).
"""
get_levels(domains::AbstractVector{Tuple{Int,Int}}) = [ui - li + 1 for (li, ui) in domains]

function get_levels(solver::Optimizer{T}, device::DIRAC_3{T}, vars) where {T}
    return get_levels(variable_domains(solver, device, vars))
end

@doc raw"""
    assert_level_budget(num_levels::AbstractVector{<:Integer}, limit::Integer)

Check the per-variable level counts against the total level budget of the
current allocation (see `qci_max_level`), which the device enforces across all
variables of a job.

The total is accumulated in `BigInt`: per-variable counts that are individually
representable can still sum past `typemax(Int)`, and a wrapped negative total
would compare below any budget and let the job through.
"""
function assert_level_budget(num_levels::AbstractVector{<:Integer}, limit::Integer)
    if any(<(one(eltype(num_levels))), num_levels)
        error(
            "DIRAC-3 needs at least one level per variable, but the requested counts " *
            "include $(minimum(num_levels)). This usually means a variable's bounds " *
            "describe an empty or unrepresentable domain.",
        )
    end

    total = sum(BigInt, num_levels; init = big(0))

    if total > limit
        error(
            "This model needs $(total) DIRAC-3 levels across $(length(num_levels)) " *
            "variables, exceeding the $(limit)-level budget of the current allocation. " *
            "Tighten the variable bounds or use fewer variables.",
        )
    end

    return nothing
end

@doc raw"""
    readjust_poly_values(solver::Optimizer{T}, device::DIRAC_3{T}, vars, samples::Vector{Sample{T,T}}, sense) where {T}

Map provider sample points back to the original variable domain (adding each
variable's transformed lower bound, see [`variable_domains`](@ref)) and
recompute objective values from the stored polynomial, restoring the original
model's objective for `MAX_SENSE` models. Returns the samples ordered
best-first for the given sense.
"""
function readjust_poly_values(solver::Optimizer{T}, device::DIRAC_3{T}, vars, samples::Vector{Sample{T,T}}, sense) where {T}
    adjusted_samples = sizehint!(Sample{T,T}[], length(samples))

    # Inverts the substitution `rescale_variables` applied, so both must read
    # the same lower bound.
    domains = variable_domains(solver, device, vars)

    for sample in samples
        point = Vector{T}(undef, length(vars))
        x     = Vector{PolyVar}(undef, length(vars))

        for (xi, (li, _)) in zip(vars, domains)
            vi = var_inv(device.varmap, xi)
            i  = var_idx(device.varmap, vi)

            point[i] = sample.point[i] + li
            x[i]     = xi
        end

        # `device.poly` stores the minimization form, which is the negated
        # objective for MAX_SENSE models; the sign flip below restores the
        # original model's objective value at the sampled point.
        value = if sense === MOI.MAX_SENSE
            -device.poly(x => point)
        else # MOI.MIN_SENSE
            device.poly(x => point)
        end

        push!(adjusted_samples, Sample{T,T}(point, value, sample.reads))
    end

    return sort_samples!(adjusted_samples, sense)
end
