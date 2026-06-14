using JSON
using QCIOpt

import PythonCall

const TIMING_KEY = r"(time|timing|runtime|elapsed|duration|created|started|submitted|queued|running|completed|finished|rfc3339|metrics)"i
const STATUS_KEY = r"(status|state|result|error|diagnostic|message)"i
const ID_KEY = r"(^id$|_id$|job_id|file_id)"i

function type_summary(value)
    if value isa AbstractDict
        return "Dict($(length(value)))"
    elseif value isa AbstractVector
        return "Vector($(length(value)))"
    elseif value isa AbstractString
        return "String"
    elseif isnothing(value)
        return "nothing"
    else
        return string(typeof(value))
    end
end

function sorted_keys(dict::AbstractDict)
    return sort!(String[string(key) for key in keys(dict)])
end

function walk_paths!(paths, value; prefix = "", max_depth = 6)
    if max_depth < 0
        return paths
    elseif value isa AbstractDict
        for key in sorted_keys(value)
            child = value[key]
            path = isempty(prefix) ? key : "$(prefix).$(key)"
            push!(paths, path => type_summary(child))
            walk_paths!(paths, child; prefix = path, max_depth = max_depth - 1)
        end
    elseif value isa AbstractVector
        push!(paths, "$(prefix)[]" => "element summary omitted")
        if !isempty(value)
            walk_paths!(paths, first(value); prefix = "$(prefix)[]", max_depth = max_depth - 1)
        end
    end

    return paths
end

function selected_values!(values, value; prefix = "")
    if value isa AbstractDict
        for key in sorted_keys(value)
            child = value[key]
            path = isempty(prefix) ? key : "$(prefix).$(key)"
            if occursin(TIMING_KEY, key) || occursin(STATUS_KEY, key) || occursin(ID_KEY, key)
                if !(child isa AbstractDict) && !(child isa AbstractVector)
                    push!(values, path => child)
                end
            end
            selected_values!(values, child; prefix = path)
        end
    elseif value isa AbstractVector
        for (index, child) in enumerate(value)
            index > 3 && break
            selected_values!(values, child; prefix = "$(prefix)[$index]")
        end
    end

    return values
end

function find_first_key(value, wanted::AbstractString)
    if value isa AbstractDict
        for key in sorted_keys(value)
            child = value[key]
            key == wanted && return child
            found = find_first_key(child, wanted)
            isnothing(found) || return found
        end
    elseif value isa AbstractVector
        for child in value
            found = find_first_key(child, wanted)
            isnothing(found) || return found
        end
    end

    return nothing
end

function print_section(title)
    println()
    println("## ", title)
end

function print_pairs(pairs)
    for (key, value) in pairs
        println(key, " = ", JSON.json(value))
    end
end

function capture_dirac1()
    api_token = get(ENV, "QCI_TOKEN", "")
    isempty(strip(api_token)) && error("QCI_TOKEN is required")

    QCIOpt.qci_default_token!(api_token)

    qci_client_version = PythonCall.pyconvert(
        String,
        PythonCall.pyimport("importlib.metadata").version("qci-client"),
    )

    println("qci-client version = ", qci_client_version)
    println("QCI API URL = ", QCIOpt.QCI_URL)

    matrix = [1.0 -1.0; -1.0 1.0]
    device = QCIOpt.DIRAC_1{Float64}()

    file = QCIOpt.qci_data_file(matrix)
    file_id = QCIOpt.qci_upload_file(file; api_token, silent = true)
    job_body = QCIOpt.qci_build_job_body(
        device;
        file_id,
        api_token,
        silent = true,
        device_type = "dirac-1",
        job_type = "sample-qubo",
        num_samples = 10,
    )

    response = QCIOpt.qci_process_job(job_body; api_token, verbose = false)
    job_id = find_first_key(response, "job_id")

    print_section("process_job response key paths")
    print_pairs(walk_paths!(Pair{String,String}[], response))

    print_section("process_job selected values")
    print_pairs(selected_values!(Pair{String,Any}[], response))

    if isnothing(job_id)
        println()
        println("No job_id field found in process_job response; skipping direct status/metrics calls.")
        return nothing
    end

    client_details = QCIOpt.qci_client(; api_token) do client
        status = client.get_job_status(; job_id) |> QCIOpt.jl_object
        job_response = client.get_job_response(; job_id) |> QCIOpt.jl_object

        metrics = try
            client.get_job_metrics(; job_id) |> QCIOpt.jl_object
        catch err
            Dict{String,Any}(
                "capture_error_type" => string(typeof(err)),
                "capture_error" => sprint(showerror, err),
            )
        end

        return Dict{String,Any}(
            "status" => status,
            "job_response" => job_response,
            "metrics" => metrics,
        )
    end

    for name in ("status", "job_response", "metrics")
        payload = client_details[name]

        print_section("$(name) key paths")
        print_pairs(walk_paths!(Pair{String,String}[], payload))

        print_section("$(name) selected values")
        print_pairs(selected_values!(Pair{String,Any}[], payload))
    end

    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    capture_dirac1()
end
