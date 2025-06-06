@doc raw"""
    DIRAC_3 <: QCI_DIRAC <: QCI_DEVICE

## About

"""
struct DIRAC_3 <: QCI_DIRAC end

QCI_DEVICES["dirac-3"] = DIRAC_3

const DIRAC_3_ATTRIBUTES = Set{String}([
    "num_samples",
    "relaxation_schedule",
])

qci_default_attributes(::DIRAC_3) = Dict{String,Any}(
    qci_default_attributes()...,
    "device_type"         => "dirac-3",
    "num_samples"         => 10,
    "relaxation_schedule" => 1,
)

qci_supports_attribute(::DIRAC_3, attr::AbstractString) = attr ∈ DIRAC_3_ATTRIBUTES

@doc raw"""
    qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_3; api_token::AbstractString) where {T}

    
"""
function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_3; api_token::AbstractString) where {T}
    n = MOI.get(model, MOI.NumberOfVariables())

    DP.@polyvar(x[1:n])

    for (i, vi) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
        var_map!(solver.source_map, vi, x[i])
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

    solver.poly = parse_polynomial(model, solver.source_map)

    fix  = get_fix(solver)
    poly = fix_variables(solver.poly, fix)
    vars = setdiff(x, first.(fix)) # free variables

    num_vars = length(vars)

    for j = 1:num_vars
        var_map!(solver.target_map, vars[j], j)
    end

    target_poly = rescale_variables(
        poly,
        vars,
        [solver.lower[vi] for vi in map(xi -> var_inv(solver.source_map, xi), vars)],
        [solver.upper[vi] for vi in map(xi -> var_inv(solver.source_map, xi), vars)],
    )

    num_levels = get_levels(solver, num_vars)

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

    file     = qci_data_file(xi -> var_map(solver.target_map, xi), target_poly; file_name)
    file_id  = qci_upload_file(file; api_token)
    job_body = qci_build_poly_job_body(file_id; api_token, job_params...) # TODO: Pass Parameters for this
    response = qci_process_job(job_body; api_token, verbose = !silent)
    solution = qci_get_results(T, T, response)

    # Store results
    # TODO: Store solution metadata (QCI provides a lot of details about it!)
    solver.solution = Solution{T,T}(
        readjust_poly_values(solver, n, solution.samples, MOI.get(model, MOI.ObjectiveSense())),
        solution.metadata,
    )

    return nothing
end

qci_max_level(::DIRAC_3) = qci_is_free_tier() ? 500 : 949
