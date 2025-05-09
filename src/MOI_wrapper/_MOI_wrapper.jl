struct Variables{T}
    index::Vector{VI}
    isbin::Vector{Bool}
    isint::Vector{Bool}
    lower::Vector{Union{T,Nothing}}
    upper::Vector{Union{T,Nothing}}

    function Variables{T}() where {T}
        return new(VI[], Bool[], Bool[], Union{T,Nothing}[], Union{T,Nothing}[])
    end
end

Base.length(var::Variables{T}) where {T} = length(var.index)

MOI.is_empty(var::Variables{T}) where {T} = isempty(var.index)

function MOI.empty!(var::Variables{T}) where {T}
    empty!(var.index)
    empty!(var.isbin)
    empty!(var.isint)
    empty!(var.lower)
    empty!(var.upper)

    return nothing
end

function set_bin!(var::Variables{T}, vi::VI) where {T}
    var.isbin[vi.value] = true

    set_lower_bound!(var, vi, T(0))
    set_upper_bound!(var, vi, T(1))

    set_int!(var, vi)
    
    return nothing
end

function set_int!(var::Variables{T}, vi::VI) where {T}
    var.isint[vi.value] = true

    return nothing
end

function set_lower_bound!(var::Variables{T}, vi::VI, bound::Union{T,Nothing}) where {T}
    var.lower[vi.value] = bound

    return nothing
end

function set_upper_bound!(var::Variables{T}, vi::VI, bound::Union{T,Nothing}) where {T}
    var.upper[vi.value] = bound

    return nothing
end

function MOI.add_variable(var::Variables{T}) where {T}
    vi = VI(length(var.index) + 1)

    push!(var.index, vi)
    push!(var.isbin, false)
    push!(var.isint, false)
    push!(var.lower, nothing)
    push!(var.upper, nothing)

    return vi
end

mutable struct Objective{T}
    sense::MOI.OptimizationSense
    func::SQF{T}

    function Objective{T}() where {T}
        return new(MOI.FEASIBILITY_SENSE, SQF{T}(SQT{T}[], SAT{T}[], zero(T)))
    end
end

function MOI.is_empty(obj::Objective{T}) where {T}
    return isempty(obj.func.quadratic_terms) &&
           isempty(obj.func.affine_terms) &&
           iszero(obj.func.constant)
end

function MOI.empty!(obj::Objective{T}) where {T}
    obj.sense = MOI.FEASIBILITY_SENSE
    obj.func  = SQF{T}(SQT{T}[], SAT{T}[], zero(T))

    return nothing
end

function set_sense!(obj::Objective{T}, s::MOI.OptimizationSense) where {T}
    obj.sense = s

    return nothing
end

function set_objective!(obj::Objective{T}, f::SQF{T}) where {T}
    obj.func = SQF{T}(SQT{T}[], SAT{T}[], zero(T))

    append!(obj.func.quadratic_terms, f.quadratic_terms)
    append!(obj.func.affine_terms, f.affine_terms)

    obj.func.constant = f.constant

    MOIU.canonicalize!(obj.fun)

    return nothing
end

function set_objective!(obj::Objective{T}, f::SAF{T}) where {T}
    obj.func = SQF{T}(SQT{T}[], SAT{T}[], zero(T))

    append!(obj.func.affine_terms, f.terms)

    obj.func.constant = f.constant

    MOIU.canonicalize!(obj.fun)

    return nothing
end

mutable struct Settings{T}
    api_token::Union{String,Nothing}

    function Settings{T}() where {T}
        return new(
            nothing, # api_token
        )
    end
end

function MOI.empty!(settings::Settings{T}) where {T}
    settings.api_token = nothing

    return nothing
end



function MOI.supports(opt::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    return attr.name ∈ ["api_token"]
end

function MOI.get(opt::Optimizer{T}, ::MOI.NumberOfVariables) where {T}
    return length(opt.variables.index)
end


function MOI.get(opt::Optimizer{T}, attr::MOI.RawOptimizerAttribute) where {T}
    if attr.name == "api_token"
        return opt.settings.api_token
    else
        error("Unsuported Attribute '$(attr.name)'")
    end

    return nothing
end

function MOI.set(opt::Optimizer{T}, attr::MOI.RawOptimizerAttribute, value::Any) where {T}
    if attr.name == "api_token"
        opt.settings.api_token = value
    else
        error("Unsuported Attribute '$(attr.name)'")
    end

    return nothing
end

MOI.supports_incremental_interface(::Optimizer{T}) where {T} = false

function MOI.is_empty(opt::Optimizer{T})::Bool where {T}
    return MOI.is_empty(opt.objective) && MOI.is_empty(opt.variables)
end

function MOI.empty!(opt::Optimizer{T}) where {T}
    MOI.empty!(opt.variables)
    MOI.empty!(opt.objective)

    MOI.empty!(opt.settings)

    return nothing
end

function get_qci_poly_data(opt::Optimizer{T}) where {T}
    poly_data = PythonCall.pylist()

    if !isempty(opt.objective.func.quadratic_terms)
        for t in opt.objective.func.quadratic_terms
            vi = t.variable_1
            vj = t.variable_2
            c  = t.coefficient
            
            poly_data.append(
                PythonCall.pydict(
                    idx = PythonCall.pylist([vi.value, vj.value]),
                    val = PythonCall.pyfloat(c),
                )
            )
        end
    end

    if !isempty(opt.objective.func.affine_terms)
        for t in opt.objective.func.affine_terms
            vi = t.variable
            c  = t.coefficient
            
            poly_data.append(
                PythonCall.pydict(
                    idx = PythonCall.pylist([vi.value]),
                    val = PythonCall.pyfloat(c),
                )
            )
        end
    end

    return poly_data
end

function MOI.copy_to(opt::Optimizer{T}, src::MOI.ModelLike) where {T}
    # Copied from MOI.default_copy_to:

    MOI.empty!(opt)

    index_map, vis_src, constraints_not_added = MOIU._copy_variables_with_set(opt, src)

    # Copy variable attributes
    MOIU.pass_attributes(opt, src, index_map, vis_src)

    # Copy model attributes
    MOIU.pass_attributes(opt, src, index_map)

    # Copy optimizer attributes
    for attr in MOI.get(src, MOI.ListOfOptimizerAttributesSet())
        MOI.set(opt, attr, MOI.get(src, attr))
    end

    # Copy constraints
    MOIU._pass_constraints(opt, src, index_map, constraints_not_added)

    MOIU.final_touch(opt, index_map)

    return index_map
end

function MOI.optimize!(opt::Optimizer{T}) where {T}
    let client = qcic.QciClient(; api_token = opt.settings.api_token, url = QCI_URL)
        poly_data = get_qci_poly_data(opt)
        json_file = PythonCall.pydict(
            file_name   = "jump-model",
            file_config = PythonCall.pydict(
                polynomial = PythonCall.pydict(
                    num_variables = PythonCall.pyint(MOI.get(opt, MOI.NumberOfVariables())),
                    min_degree    = PythonCall.pyint(minimum(t -> length(t["idx"]), poly_data)),
                    max_degree    = PythonCall.pyint(maximum(t -> length(t["idx"]), poly_data)),
                    data          = poly_data,
                )
            )
        )

        @show file_response = client.upload_file(file=json_file)
        client.build_job_body(
            job_type="sample-hamiltonian-integer",
            job_name="test_integer_variable_hamiltonian_job", # user-defined string, optional
            job_tags=["tag1", "tag2"],  # user-defined list of string identifiers, optional
            job_params={
                "device_type": "dirac-3",
                "num_samples": 5,
                "relaxation_schedule": 1,
                "num_levels": [5, 2],  # For demonstration, this excludes some but not all of the known local minima.
            },
            polynomial_file_id=file_response_int_problem["file_id"],
)
    end

    return nothing
end

MOI.supports(
    opt::Optimizer{T},
    ::MOI.ObjectiveSense
) where {T} = true

function MOI.set(opt::Optimizer{T}, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense) where {T}
    set_sense!(opt.objective, sense)

    @assert sense === MOI.MIN_SENSE

    return nothing
end

MOI.supports(
    opt::Optimizer{T},
    ::MOI.ObjectiveFunction{F},
) where {T,F<:Union{SAF{T},SQF{T}}} = true

function MOI.set(opt::Optimizer, ::MOI.ObjectiveFunction{F}, f::F) where {T,F<:Union{SAF{T},SQF{T}}}
    set_objective!(opt.objective, f)

    return nothing
end

MOI.supports_constraint(
    opt::Optimizer{T},
    ::Type{VI},
    ::Type{MOI.ZeroOne},
) where {T} = true

MOI.supports_constraint(
    opt::Optimizer{T},
    ::Type{VI},
    ::Type{MOI.Integer},
) where {T} = true

MOI.supports_constraint(
    opt::Optimizer{T},
    ::Type{VI},
    ::Type{S},
) where {T,S<:Union{EQ{T},GT{T},LT{T}}} = true

function MOI.add_variable(opt::Optimizer{T})::VI where {T}
    return MOI.add_variable(opt.variables)
end

function MOI.add_constraint(opt::Optimizer{T}, vi::VI, ::MOI.ZeroOne) where {T}
    set_bin!(opt.variables, vi)

    return CI{VI,MOI.ZeroOne}(vi.value)
end

function MOI.add_constraint(opt::Optimizer{T}, vi::VI, ::MOI.Integer) where {T}
    set_int!(opt.variables, vi)

    return CI{VI,MOI.Integer}(vi.value)
end

function MOI.add_constraint(opt::Optimizer{T}, vi::VI, c::MOI.GreaterThan{T}) where {T}
    set_lower_bound!(opt.variables, vi, c.lower)

    return CI{VI,MOI.GreaterThan{T}}(vi.value)
end

function MOI.add_constraint(opt::Optimizer{T}, vi::VI, c::MOI.LessThan{T}) where {T}
    set_upper_bound!(opt.variables, vi, c.upper)

    return CI{VI,MOI.LessThan{T}}(vi.value)
end

# function get_qci_poly_data(L, Q) where {T}
#     poly_data = PythonCall.pylist()

#     for ((vi, vj), cij) in Q
#         poly_data.append(
#             PythonCall.pydict(
#                 idx = PythonCall.pylist([vi, vj]),
#                 val = PythonCall.pyfloat(cij),
#             )
#         )
#     end

#     for (vi, ci) in L
#         poly_data.append(
#             PythonCall.pydict(
#                 idx = PythonCall.pylist([vi]),
#                 val = PythonCall.pyfloat(ci),
#             )
#         )
#     end

#     return poly_data
# end

# function get_qci_json_file(n::Integer, poly_data)
#     json_file = PythonCall.pydict(
#         file_name   = "jump-model",
#         file_config = PythonCall.pydict(
#             polynomial = PythonCall.pydict(
#                 num_variables = PythonCall.pyint(n),
#                 min_degree    = PythonCall.pyint(minimum(t -> length(t["idx"]), poly_data)),
#                 max_degree    = PythonCall.pyint(maximum(t -> length(t["idx"]), poly_data)),
#                 data          = poly_data,
#             )
#         )
#     )

#     return json_file
# end
