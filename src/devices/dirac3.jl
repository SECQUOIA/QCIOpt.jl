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

@doc raw"""
    qci_load!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike) where {T}

Load the model into the device without touching the network: build the
variable map, retrieve variable bounds, copy model attributes, and parse the
objective polynomial. The device natively minimizes, so for `MAX_SENSE` models
the negated polynomial is stored and submitted; original objective values are
restored in [`readjust_poly_values`](@ref).

Returns the vector of `DynamicPolynomials` variables in model variable order.
"""
function qci_load!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike) where {T}
    n = MOI.get(model, MOI.NumberOfVariables())

    DP.@polyvar(x[1:n])

    for (i, vi) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
        var_map!(device.varmap, vi, x[i])
    end

    # TODO: Adjust variable bounds
    # (see `DynamicPolynomials.subs` @ https://juliaalgebra.github.io/MultivariatePolynomials.jl/stable/substitution/)
    # This has to return:
    # 1. A new, modified polynomial such that each original variable xᵢ ∈ [l, u] becomes xᵢ ∈ [0, u - l] under
    #    the substitution rule xᵢ ↦ (xᵢ - l) for the integer case and xᵢ ↦ (xᵢ - l) / (u - l) for the real case
    #    where xᵢ ∈ [0, 1] (to be rescaled later according to variable precision)
    # 2. The new variable bounds, to be passed as qci_build_job_body(...; ..., num_levels = variable_bounds::Vector{Int})
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
    qci_optimize!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}

Submit the loaded model to the DIRAC-3 device and store the parsed results.
"""
function qci_optimize!(solver::Optimizer{T}, device::DIRAC_3{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}
    x = qci_load!(solver, device, model)

    poly = rescale_variables(
        device.poly,
        x,
        [solver.lower[vi] for vi in map(xi -> var_inv(device.varmap, xi), x)],
        [solver.upper[vi] for vi in map(xi -> var_inv(device.varmap, xi), x)],
    )

    num_levels = get_levels(solver, device, x)

    @assert sum(num_levels) <= qci_max_level(device)
    
    silent              = MOI.get(solver, MOI.Silent())
    file_name           = MOI.get(solver, MOI.RawOptimizerAttribute("file_name"))
    num_samples         = MOI.get(solver, MOI.RawOptimizerAttribute("num_samples"))
    relaxation_schedule = MOI.get(solver, MOI.RawOptimizerAttribute("relaxation_schedule"))

    job_params = Dict{Symbol,Any}(
        :device_type         => "dirac-3",
        :job_type            => "sample-hamiltonian-integer",
        :num_levels          => num_levels,
        :num_samples         => num_samples,
        :relaxation_schedule => relaxation_schedule,
    )

    file     = qci_data_file(xi -> var_idx(device.varmap, var_inv(device.varmap, xi)), poly; file_name)
    file_id  = qci_upload_file(file; api_token)
    job_body = qci_build_poly_job_body(file_id; api_token, job_params...) # TODO: Pass Parameters for this
    response = qci_process_job(job_body; api_token, verbose = !silent)
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

qci_max_level(::DIRAC_3) = qci_is_free_tier() ? 500 : 949

function get_levels(solver::Optimizer{T}, device::DIRAC_3{T}, vars) where {T}
    return map(
        xi -> let vi = var_inv(device.varmap, xi)
            1 + (floor(Int, solver.upper[vi]) - ceil(Int, solver.lower[vi]))
        end,
        vars,
    )
end

@doc raw"""
    readjust_poly_values(solver::Optimizer{T}, device::DIRAC_3{T}, vars, samples::Vector{Sample{T,T}}, sense) where {T}

Map provider sample points back to the original variable domain (adding each
variable's lower bound) and recompute objective values from the stored
polynomial, restoring the original model's objective for `MAX_SENSE` models.
Returns the samples ordered best-first for the given sense.
"""
function readjust_poly_values(solver::Optimizer{T}, device::DIRAC_3{T}, vars, samples::Vector{Sample{T,T}}, sense) where {T}
    adjusted_samples = sizehint!(Sample{T,T}[], length(samples))

    for sample in samples
        point = Vector{T}(undef, length(vars))
        x     = Vector{PolyVar}(undef, length(vars))

        for xi in vars
            vi = var_inv(device.varmap, xi)
            i  = var_idx(device.varmap, vi)

            li = solver.lower[vi]

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
