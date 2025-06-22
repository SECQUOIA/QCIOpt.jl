@doc raw"""
    DIRAC_1

## About

"""
mutable struct DIRAC_1{T} <: QCI_DIRAC
    varmap::VarMap{VI,Int}
    matrix::Matrix{T}
    offset::T
    config::Dict{String,Any}
end

function qci_config!(device::DIRAC_1{T}, attr::String, val::Any) where {T}
    @assert qci_supports_attribute(device, attr)

    device.config[attr] = val

    return nothing
end

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

qci_supports_attribute(::DIRAC_1, attr::AbstractString) = (attr ∈ DIRAC_1_ATTRIBUTES)

function assert_is_qubo_model(model::MOI.ModelLike)
    let F = MOI.get(model, MOI.ObjectiveFunctionType())
        @assert (F isa SQF || F isa SAF || F isa VI)
    end

    var_set = Set{VI}(MOI.ListOfVariableIndices())
    bin_set = sizehint!(Set{VI}(), length(var_set))

    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI,MOI.ZeroOne}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)

        push!(bin_set, vi)
    end

    @assert (var_set ⊆ bin_set)

    return nothing
end

function load_attributes!(device::QCI_DEVICE, solver::Optimizer{T}, model::MOI.ModelLike) where {T}
    load_attributes!(solver, model)
    load_attributes!(device, model)

    return nothing
end

function load_attributes!(device::DIRAC_1{T}, model::MOI.ModelLike) where {T}
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


function qci_load!(device::DIRAC_1{T}, solver::Optimizer{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}
    n = MOI.get(model, MOI.NumberOfVariables())

    for (i, vi) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
        var_map!(solver.source_map, vi, i)
    end

    assert_is_qubo_model(model)

    qci_config!(device, "api_token", api_token)

    load_attributes!(device, solver, model)

    return nothing
end

function qci_optimize!(device::DIRAC_1{T}, solver::Optimizer{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}
    qci_load!(device, solver, model; api_token)

    

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
