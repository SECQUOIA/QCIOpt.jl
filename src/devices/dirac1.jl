@doc raw"""
    DIRAC_1

## About

"""
struct DIRAC_1 <: QCI_DIRAC end

QCI_DEVICES["dirac-1"] = DIRAC_1

const DIRAC_1_ATTRIBUTES = Set{String}([
    "num_samples",
    "relaxation_schedule",
])

qci_default_attributes(::DIRAC_1) = Dict{String,Any}(
    qci_default_attributes()...,
    "device_type"         => "dirac-1",
    "num_samples"         => 10,
    "relaxation_schedule" => 1,
)

qci_supports_attribute(::DIRAC_1, attr::AbstractString) = attr ∈ DIRAC_1_ATTRIBUTES


function qci_optimize!(solver::Optimizer{T}, model::MOI.ModelLike, device::DIRAC_1; api_token::AbstractString) where {T}
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

    # check if variables are all binary
    @assert all(l -> l == 0, values(solver.lower))
    @assert all(u -> u == 1, values(solver.upper))

    copy_model_attributes!(solver, model)

    solver.qubo = let
        F = MOI.get(model, MOI.ObjectiveFunctionType())
        f = MOI.get(model, MOI.ObjectiveFunction{F}())

        parse_qubo_matrix(f, solver.source_map)
    end

    fix  = get_fix(solver)
    qubo = let (Q, c) = fix_variables(first(solver.qubo), fix)
        (Q, c + last(solver.qubo))
    end
    vars = setdiff(x, first.(fix)) # free variables

    num_vars = length(vars)

    for j = 1:num_vars
        var_map!(solver.target_map, vars[j], j)
    end

    @assert num_vars <= qci_max_level(device)
    
    silent              = MOI.get(solver, MOI.Silent())
    file_name           = MOI.get(solver, MOI.RawOptimizerAttribute("file_name"))
    num_samples         = MOI.get(solver, MOI.RawOptimizerAttribute("num_samples"))
    # relaxation_schedule = MOI.get(solver, MOI.RawOptimizerAttribute("relaxation_schedule"))

    job_params = Dict{Symbol,Any}(
        :device_type => "dirac-1",
        :job_type    => "sample-qubo",
        :num_samples => num_samples,
    )

    file     = qci_data_file(first(qubo); file_name)
    file_id  = qci_upload_file(file; api_token)
    job_body = qci_build_qubo_job_body(file_id; api_token, job_params...) # TODO: Pass Parameters for this
    response = qci_process_job(job_body; api_token, verbose = !silent)
    solution = qci_get_results(T, T, response)

    # Store results
    # TODO: Store solution metadata (QCI provides a lot of details about it!)
    solver.solution = Solution{T,T}(
        readjust_qubo_values(solver, n, solution.samples, MOI.get(model, MOI.ObjectiveSense())),
        solution.metadata,
    )

    return nothing
end

qci_max_level(::DIRAC_1) = 500
