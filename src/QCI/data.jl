
@doc raw"""
    QCI_QUBO_DATA{T}
"""
struct QCI_QUBO_DATA{T}
    data::Matrix{T}
end

function qci_qubo_data(Q::AbstractMatrix{T}) where {T}
    m, n = size(Q)

    @assert m == n
    @assert issymmetric(Q)

    return QCI_QUBO_DATA{T}(Q)
end

function qci_data_file(Q::AbstractMatrix{T}; file_name::Union{AbstractString,Nothing} = nothing) where {T}
    qubo = qci_qubo_data(Q)
    file = Dict{String,Any}(
        "file_name"   => "smallest_objective.json",
        "file_config" => Dict{String,Any}(
            "qubo" => Dict{String,Any}(
                "data" => np.array(qubo.data),
            )
        )
    )

    if !isnothing(file_name)
        open(file_name, "w") do io
            println(io, JSON.json(file, 4))
        end
    end

    return file
end

@doc raw"""
    QCI_POLY_DATA{T}
"""
struct QCI_POLY_DATA{T}
    num_variables::Int
    min_degree::Int
    max_degree::Int
    data::Vector{Dict{String,Any}}
end

function qci_poly_data(indices::AbstractVector{V}, values::AbstractVector{T}) where {T,V<:AbstractVector{<:Integer}}
    @assert length(indices) == length(values)

    first_iter    = true
    term_size     = nothing
    num_variables = 0
    min_degree    = nothing
    max_degree    = nothing
    data          = Dict{String,Any}[]

    for (idx, val) in zip(indices, values)
        if first_iter
            term_size     = length(idx)
            num_variables = maximum(idx)
            degree        = count(i -> i > 0, idx)
            min_degree    = degree
            max_degree    = degree

            first_iter    = false
        else
            @assert length(idx) == term_size

            num_variables = max(num_variables, maximum(idx))
            degree        = count(i -> i > 0, idx)
            min_degree    = min(min_degree, degree)
            max_degree    = max(max_degree, degree)
        end

        push!(data, Dict{String,Any}("idx" => idx, "val" => val))
    end

    return QCI_POLY_DATA{T}(
        num_variables,
        min_degree,
        max_degree,
        data,
    )
end

function qci_data_file(
    indices,
    values;
    file_name::Union{AbstractString,Nothing} = nothing,
    num_variables::Union{Integer,Nothing} = nothing,
)
    poly = qci_poly_data(indices, values)
    declared_num_variables = something(num_variables, poly.num_variables)
    if declared_num_variables < poly.num_variables
        throw(
            ArgumentError(
                "declared num_variables = $(declared_num_variables) is below the " *
                "highest variable index present in the polynomial " *
                "($(poly.num_variables))",
            ),
        )
    end

    file = Dict{String,Any}(
        "file_name"   => something(file_name, ""),
        "file_config" => Dict{String,Any}(
            "polynomial" => Dict{String,Any}(
                "num_variables" => declared_num_variables,
                "min_degree"    => poly.min_degree,
                "max_degree"    => poly.max_degree,
                "data"          => poly.data,
            )
        )
    )

    if !isnothing(file_name)
        open(file_name, "w") do io
            println(io, JSON.json(file, 4))
        end
    end

    return file
end

function qci_data_file(
    varmap::Function,
    p::DP.Polynomial{_V,_M,T};
    file_name::Union{AbstractString,Nothing} = nothing,
    num_variables::Union{Integer,Nothing} = nothing,
) where {_V,_M,T}
    indices = Vector{Int}[]
    values  = T[]
    degree  = DP.maxdegree(p)

    for t in DP.terms(p)
        val = DP.coefficient(t)
        idx = sizehint!(Int[], degree)

        for (v, d) in DP.powers(t)
            i = varmap(v)::Integer

            for _ = 1:d
                push!(idx, i)
            end
        end

        if length(idx) == 0 # skip constant terms
            continue
        end

        while length(idx) < degree
            push!(idx, 0)
        end

        push!(indices, sort!(idx))
        push!(values, val)
    end

    return qci_data_file(indices, values; file_name, num_variables)
end

function qci_data_file(p::DP.Polynomial{T}; file_name::Union{AbstractString,Nothing} = nothing) where {T}
    varmap = Dict{DP.Variable,Int}(x => i for (i, x) in enumerate(DP.variables(p)))

    return qci_data_file(x -> varmap[x]::Int, p; file_name)
end

@doc raw"""
    qci_parse_results(::Type{U}, ::Type{T}, response) where {U,T}

Turn a QCI job response into a `Solution`: the sampled points for a
`COMPLETED` job, and no samples for any other provider status. The response is
kept verbatim as the solution metadata in every case, which is what preserves
the job identity, timing, and diagnostic fields that
[`qci_provider_metadata`](@ref) reads back out.

Only `status` is required of the response. Every other field is optional, so an
`ERRORED` job that carries no diagnostic message still returns with its status
intact instead of failing on a missing field.
"""
function qci_parse_results(::Type{U}, ::Type{T}, response) where {U, T}
    status = qci_response_field(response, "status")

    if status == "COMPLETED"
        res = qci_provider_results(response)

        samples = map(
            (x, v, r) -> Sample{U,T}(Vector{U}(x), convert(T, v), r),
            res["solutions"],
            res["energies"],
            res["counts"],
        )

        return Solution{U,T}(samples, response)
    elseif status == "ERRORED"
        @error(
            something(
                qci_provider_error(response),
                "QCI reported an ERRORED job without a job-error message.",
            )
        )

        return Solution{U,T}(Sample{U,T}[], response)
    else
        return Solution{U,T}(Sample{U,T}[], response)
    end
end

@doc raw"""
    qci_provider_results(response)

Return the `results` payload of a `COMPLETED` job response, checking that it
carries the sample fields QCIOpt reads and that they agree on length.

A `COMPLETED` job always carries results, so a response that does not is a
provider-contract violation rather than an optional field: it fails here, naming
the reported status and the offending field, instead of surfacing as a
`KeyError` or a length mismatch from deeper in the parse.
"""
function qci_provider_results(response)
    res = qci_response_field(response, "results")

    if !(res isa AbstractDict)
        error(
            "QCI reported a COMPLETED job whose response carries no 'results' " *
            "payload (got $(repr(res))).",
        )
    end

    for key in ("solutions", "energies", "counts")
        haskey(res, key) || error(
            "QCI reported a COMPLETED job whose 'results' payload is missing " *
            "'$(key)'.",
        )
    end

    lengths = Dict(key => length(res[key]) for key in ("solutions", "energies", "counts"))

    if !allequal(values(lengths))
        error(
            "QCI reported a COMPLETED job whose 'results' fields disagree on " *
            "length: $(join(("$(key) => $(lengths[key])" for key in ("solutions", "energies", "counts")), ", ")).",
        )
    end

    return res
end
