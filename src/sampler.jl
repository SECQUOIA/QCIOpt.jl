QUBODrivers.@setup Optimizer begin
    name       = "QCInc Dirac-3"
    attributes = begin
        APIToken["api_token"]::Union{String,Nothing}       = nothing
        NumberOfReads["num_reads"]::Integer                = 10
        # RelaxationSchedule["relaxation_schedule"]::Integer = 1
        DeviceType["device_type"]::String                  = "dirac-1"
    end
end 

function QUBODrivers.sample(opt::Optimizer{T}) where {T}
    n, L, Q, α, β = QUBOTools.qubo(opt, :sparse; sense = :min)

    num_reads           = MOI.get(opt, QCIOpt.NumberOfReads()); @assert 1 <= num_reads <= 100
    api_token           = MOI.get(opt, QCIOpt.APIToken())
    device_type         = MOI.get(opt, QCIOpt.DeviceType());    @assert device_type ∈ ("dirac-1",) #, "dirac-3")
    # relaxation_schedule = MOI.get(opt, QCIOpt.RelaxationSchedule())

    qubo_matrix = np.array(diagm(L) + Symmetric(Q / 2))
    json_file   = PythonCall.pydict(
        file_name   = "jump-qubo.json",
        file_config = PythonCall.pydict(qubo = PythonCall.pydict(data = qubo_matrix))
    )

    # num_levels = PythonCall.pylist([1])

    # poly_data = get_qci_poly_data(L, Q)
    # json_file = get_qci_json_file(n, poly_data)

    client = qcic.QciClient(; api_token, url = QCI_URL)

    file_response = client.upload_file(; file = json_file)

    job_body = client.build_job_body(
        job_type   = "sample-qubo",
        # job_name = "test_integer_variable_hamiltonian_job", # user-defined string, optional
        # job_tags = ["tag1", "tag2"],  # user-defined list of string identifiers, optional
        job_params = PythonCall.pydict(
            device_type         = device_type,
            num_samples         = num_reads,
            # relaxation_schedule = relaxation_schedule,
            # num_levels          = num_levels, # For demonstration, this excludes some but not all of the known local minima.
        ),
        qubo_file_id = file_response["file_id"],
    )

    t = @timed begin
        job_response = client.process_job(; job_body)

        if job_response["status"] == "ERROR"
            error(job_response["job_info"]["results"]["error"])
        end

        job_response
    end

    job_response = t.value
    job_results  = job_response["results"]

    samples = QUBOTools.Sample{T,Int}[]

    for (x, k) in zip(job_results["solutions"], job_results["counts"])
        ψ = PythonCall.pyconvert(Vector{Int}, x)
        λ = QUBOTools.value(ψ, L, Q, α, β)
        r = PythonCall.pyconvert(Int, k)

        push!(samples, QUBOTools.Sample{T,Int}(ψ, λ, r))
    end
    
    metadata = Dict{String,Any}(
        "origin" => "QCI @ $(device_type)",
        "time"   => Dict{String,Any}(
            "total" => t.time,
        )
    )

    return QUBOTools.SampleSet{T,Int}(samples, metadata; sense = :min, domain = :bool)
end
