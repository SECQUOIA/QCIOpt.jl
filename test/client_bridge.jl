@testset "QCI client compatibility bridge" begin
    bridge_version = "qciopt-bridge-$(pkgversion(QCIOpt))"

    @test QCIOpt.PythonCall.pyconvert(String, QCIOpt.qcic.__name__) == "qciopt_client"
    @test QCIOpt.PythonCall.pyconvert(String, QCIOpt.qcic.__version__) == bridge_version
    @test QCIOpt.PythonCall.pyconvert(
        String,
        QCIOpt.qcic.__qci_client_parity_version__,
    ) == "5.0.0"
    @test QCIOpt.DiracSampler.qci_client_bridge_version() == bridge_version
    @test MOI.get(QCIOpt.Optimizer(), MOI.SolverVersion()) == pkgversion(QCIOpt)

    qubo_file = QCIOpt.qci_data_file([1.0 -0.5; -0.5 2.0])
    converted = QCIOpt.jl_object(QCIOpt.qcic._data_to_json(QCIOpt.py_object(qubo_file)))
    qubo = converted["file_config"]["qubo"]

    @test qubo["num_variables"] == 2
    @test qubo["data"] == [
        Dict{String,Any}("i" => 0, "j" => 0, "val" => 1.0),
        Dict{String,Any}("i" => 0, "j" => 1, "val" => -0.5),
        Dict{String,Any}("i" => 1, "j" => 0, "val" => -0.5),
        Dict{String,Any}("i" => 1, "j" => 1, "val" => 2.0),
    ]

    metadata =
        QCIOpt.jl_object(QCIOpt.qcic._metadata_body(QCIOpt.py_object(converted)))
    @test metadata == Dict{String,Any}(
        "file_name" => "smallest_objective.json",
        "file_config" => Dict{String,Any}(
            "qubo" => Dict{String,Any}("num_variables" => 2),
        ),
    )

    parts = QCIOpt.jl_object(
        QCIOpt.PythonCall.pybuiltins.list(
            QCIOpt.qcic._file_parts(QCIOpt.py_object(converted)),
        ),
    )
    @test length(parts) == 1
    @test parts[1][2] == 1
    @test parts[1][1]["file_config"]["qubo"]["data"] == qubo["data"]

    qubo_body = QCIOpt.qci_build_job_body(
        QCIOpt.DIRAC_1{Float64}();
        file_id = "qubo-file",
        api_token = "offline-token",
        num_samples = 7,
    )
    qubo_submission = qubo_body["job_submission"]

    @test qubo_submission["problem_config"] ==
        Dict{String,Any}(
            "quadratic_unconstrained_binary_optimization" =>
                Dict{String,Any}("qubo_file_id" => "qubo-file"),
        )
    @test qubo_submission["device_config"] ==
        Dict{String,Any}("dirac-1" => Dict{String,Any}("num_samples" => 7))

    polynomial_body = QCIOpt.qci_build_poly_job_body(
        "polynomial-file";
        api_token = "offline-token",
        device_type = "dirac-3",
        job_type = "sample-hamiltonian-integer",
        num_levels = [2, 3],
        relaxation_schedule = 4,
    )
    polynomial_submission = polynomial_body["job_submission"]

    @test polynomial_submission["problem_config"] ==
        Dict{String,Any}(
            "qudit_hamiltonian_optimization" =>
                Dict{String,Any}("polynomial_file_id" => "polynomial-file"),
        )
    @test polynomial_submission["device_config"] ==
        Dict{String,Any}(
            "dirac-3_qudit" => Dict{String,Any}(
                "num_samples" => 100,
                "num_levels" => [2, 3],
                "relaxation_schedule" => 4,
            ),
        )

    unauthorized = QCIOpt.qcic.requests.Response()
    unauthorized.status_code = 401
    unauthorized.reason = "Unauthorized"
    unauthorized.url = "https://api.qci-prod.com/test"
    unauthorized._content =
        QCIOpt.PythonCall.pybuiltins.bytes("{\"message\":\"Unauthorized\"}", "utf-8")
    http_error = try
        QCIOpt.qcic._raise_for_status(unauthorized)
        nothing
    catch error
        error
    end

    @test QCIOpt.qci_parse_error(http_error) isa QCIOpt.QCI_UNAUTHORIZED_API_TOKEN_ERROR
end
