
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

function qci_data_file(indices, values; file_name::Union{AbstractString,Nothing} = nothing)
    poly = qci_poly_data(indices, values)
    file = Dict{String,Any}(
        "file_name"   => something(file_name, ""),
        "file_config" => Dict{String,Any}(
            "polynomial" => Dict{String,Any}(
                "num_variables" => poly.num_variables,
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

function qci_data_file(varmap::Function, p::DP.Polynomial{_V,_M,T}; file_name::Union{AbstractString,Nothing} = nothing) where {_V,_M,T}
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

    return qci_data_file(indices, values; file_name)
end

function qci_data_file(p::DP.Polynomial{T}; file_name::Union{AbstractString,Nothing} = nothing) where {T}
    varmap = Dict{DP.Variable,Int}(x => i for (i, x) in enumerate(DP.variables(p)))

    return qci_data_file(x -> varmap[x]::Int, p; file_name)
end

function qci_parse_results(::Type{U}, ::Type{T}, response) where {U, T}
    if response["status"] == "COMPLETED"
        res = response["results"]

        samples = map(
            (x, v, r) -> Sample{U,T}(Vector{U}(x), convert(T, v), r),
            res["solutions"],
            res["energies"],
            res["counts"],
        )

        return Solution{U,T}(samples, response)
    elseif response["status"] == "ERRORED"
        @error(response["job_info"]["job_result"]["error"])

        return Solution{U,T}(Sample{U,T}[], response)
    else
        return Solution{U,T}(Sample{U,T}[], response)
    end
end
