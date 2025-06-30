@doc raw"""
    DIRAC_1

## About

"""
mutable struct DIRAC_1{T} <: QCI_DIRAC
    varmap::VarMap{VI,Int}
    matrix::Maybe{Matrix{T}}
    offset::Maybe{T}
    config::Dict{String,Any}

    function DIRAC_1{T}() where {T}
        return new{T}(VarMap{VI,Int}(), nothing, nothing, Dict{String,Any}())
    end
end

function Base.isempty(device::DIRAC_1{T}) where {T}
    return isempty(device.varmap) && isnothing(device.poly)
end

function Base.empty!(device::DIRAC_1{T}) where {T}
    empty!(device.varmap)
    device.matrix = nothing
    device.offset = nothing

    return device
end


function qci_config(device::DIRAC_1{T}, attr::AbstractString) where {T}
    @assert qci_supports_attribute(device, attr)

    return device.config[attr]
end

function qci_config!(device::DIRAC_1{T}, attr::AbstractString, val::Any) where {T}
    @assert qci_supports_attribute(device, attr)

    device.config[attr] = val

    return nothing
end

QCI_DEVICES["dirac-1"] = DIRAC_1

const DIRAC_1_ATTRIBUTES = Set{String}([
    "num_samples",
    "relaxation_schedule",
])

qci_default_attributes(::Type{DIRAC_1{T}}) where {T} = Dict{String,Any}(
    qci_default_attributes()...,
    "device_type"         => "dirac-1",
    "num_samples"         => 10,
    "relaxation_schedule" => 1,
)

qci_supports_attribute(::DIRAC_1, attr::AbstractString) = (attr ∈ DIRAC_1_ATTRIBUTES)

function assert_is_qubo_model(model::MOI.ModelLike)
    is_qubo = true

    let F = MOI.get(model, MOI.ObjectiveFunctionType())
        is_qubo &= (F isa SQF || F isa SAF || F isa VI)
    end

    var_set = Set{VI}(MOI.ListOfVariableIndices())
    bin_set = sizehint!(Set{VI}(), length(var_set))

    for ci in MOI.get(model, MOI.ListOfConstraintIndices{VI,MOI.ZeroOne}())
        vi = MOI.get(model, MOI.ConstraintFunction(), ci)

        push!(bin_set, vi)
    end

    is_qubo &= (var_set ⊆ bin_set)

    is_qubo || error("Dirac 1 only supports QUBO models.")

    return nothing
end

function load_attributes!(solver::Optimizer{T}, device::DIRAC_1{T}, model::MOI.ModelLike) where {T}
    for attr in MOI.get(model, MOI.ListOfModelAttributesSet())
        attr isa MOI.ObjectiveSense        && continue
        attr isa MOI.ObjectiveFunction     && continue
        # attr isa MOI.ObjectiveFunctionType && continue

        MOI.set(solver, attr, MOI.get(model, attr))
    end

    for attr in MOI.get(model, MOI.ListOfOptimizerAttributesSet())
        if attr isa RawOptimizerAttribute
            qci_config!(device, attr.name, MOI.get(model, attr))
        else
            MOI.set(solver, attr, MOI.get(model, attr))
        end
    end

    return nothing
end

function qci_load!(solver::Optimizer{T}, device::DIRAC_1{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}
    for (i, vi) in enumerate(MOI.get(model, MOI.ListOfVariableIndices()))
        var_map!(device.varmap, vi, i)
    end

    assert_is_qubo_model(model)

    qci_config!(device, "api_token", api_token)

    load_attributes!(solver, device, model)

    # load matrix
    device.matrix, device.offset = let
        F = MOI.get(model, MOI.ObjectiveFunctionType())
        f = MOI.get(model, MOI.ObjectiveFunction{F}())

        parse_qubo_matrix(f, device.varmap)
    end

    # TODO: Implement fixed variables
    fix = get_fix(solver)

    @assert isempty(fix)

    return nothing
end

function qci_optimize!(solver::Optimizer{T}, device::DIRAC_1{T}, model::MOI.ModelLike; api_token::AbstractString) where {T}
    qci_load!(solver, device, model; api_token)

    num_vars = size(device.matrix, 1)

    @assert num_vars <= qci_max_level(device)
    
    silent      = MOI.get(solver, MOI.Silent())
    file_name   = MOI.get(solver, MOI.RawOptimizerAttribute("file_name"))
    num_samples = MOI.get(solver, MOI.RawOptimizerAttribute("num_samples"))

    job_params = Dict{Symbol,Any}(
        :device_type => "dirac-1",
        :job_type    => "sample-qubo",
        :num_samples => num_samples,
    )

    @show device.varmap
    @show device.matrix
    @show device.offset
    @show device.config
    @show job_params

    return nothing

    file     = qci_data_file(device.matrix; file_name)
    file_id  = qci_upload_file(file; api_token)
    job_body = qci_build_job_body(device; file_id, api_token, job_params...) # TODO: Pass Parameters for this
    response = qci_process_job(job_body; api_token, verbose = !silent)
    solution = qci_parse_results(T, T, response)

    # Store results
    # TODO: Store solution metadata (QCI provides a lot of details about it!)
    solver.solution = readjust_solution(device, solution, MOI.get(solver, MOI.ObjectiveSense()))

    return nothing
end

function readjust_solution(device::DIRAC_1{T}, solution::Solution{T,T}, sense::MOI.OptimizationSense) where {T}
    return Solution{T,T}(readjust_qubo_values(device, solution.samples, sense), solution.metadata)
end

function readjust_qubo_values(device::DIRAC_1{T}, samples::Vector{Sample{T,T}}, sense::MOI.OptimizationSense) where {T}
    adjusted_samples = sizehint!(Sample{T,T}[], length(samples))

    for sample in samples
        value = (sample.point' * device.matrix * sample.point + device.offset)

        if sense === MOI.MAX_SENSE
            value *= -1
        end

        push!(adjusted_samples, Sample{T,T}(point, value, sample.reads))
    end

    return sort!(adjusted_samples; by = s -> (s.value, -s.reads))
end

function qci_build_job_body(
    ::DIRAC_1{T};
    file_id::AbstractString,
    # Client Arguments
    url::AbstractString       = QCI_URL,
    api_token::AbstractString = QCI_TOKEN[],
    silent::Bool              = false,
    # Job Arguments
    device_type::AbstractString = "dirac-1",
    job_type::AbstractString    = "sample-qubo",
    num_samples::Integer        = 100,
) where {T}
    job_tags   = String[]
    job_params = Dict{String,Any}(
        "device_type" => device_type,
        "num_samples" => num_samples,
    )

    return qci_client(; url, api_token, silent) do client
        return client.build_job_body(;
            job_type     = job_type,
            job_name     = "", # TODO: Add parameter to pass job_name
            job_tags     = py_object(job_tags),
            job_params   = py_object(job_params),
            qubo_file_id = file_id,
        ) |> jl_object
    end
end

qci_max_level(::DIRAC_1) = 10_000
