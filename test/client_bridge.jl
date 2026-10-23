function _capture_stdout(f::Function)
    original_stdout = stdout
    out_rd, out_wr = redirect_stdout()
    out_reader = @async read(out_rd, String)
    try
        f()
    finally
        redirect_stdout(original_stdout)
        close(out_wr)
    end
    return fetch(out_reader)
end

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
        Dict{String,Any}(
            "dirac-1" => Dict{String,Any}(
                "num_samples" => 7,
            ),
        )

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

    continuous_body = QCIOpt.qci_build_poly_job_body(
        "continuous-polynomial-file";
        api_token = "offline-token",
        device_type = "dirac-3",
        job_type = "sample-hamiltonian",
        sum_constraint = 2.5,
        relaxation_schedule = 3,
        num_samples = 8,
    )
    continuous_submission = continuous_body["job_submission"]

    @test continuous_submission["problem_config"] ==
        Dict{String,Any}(
            "normalized_qudit_hamiltonian_optimization" =>
                Dict{String,Any}("polynomial_file_id" => "continuous-polynomial-file"),
        )
    @test continuous_submission["device_config"] ==
        Dict{String,Any}(
            "dirac-3_normalized_qudit" => Dict{String,Any}(
                "num_samples" => 8,
                "sum_constraint" => 2.5,
                "relaxation_schedule" => 3,
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

    @testset "Provider errors are preserved across client and job operations" begin
        # Replace only the remote client boundary: no live credential is
        # required to exercise response conversion, stdout capture, and
        # HTTP-error parsing across allocation, upload, build, process, and auth.
        globals = QCIOpt.PythonCall.pydict()
        globals["unauthorized"] = unauthorized
        globals["raise_for_status"] = QCIOpt.qcic._raise_for_status
        QCIOpt.PythonCall.pyexec(
            """
            class StubClient:
                fail = False

                def __init__(self, **kwargs):
                    pass

                def _step(self, label, payload):
                    print(f"{label} progress")
                    if self.fail:
                        raise_for_status(unauthorized)
                    return payload

                def get_allocations(self):
                    return self._step("allocations", {"allocations": {"dirac": {"paid": False}}})

                def upload_file(self, *, file):
                    return self._step("upload", {"file_id": "stub-file-id"})

                def build_job_body(self, **kwargs):
                    return self._step("build", {"job_submission": {"stub": True}})

                def process_job(self, **kwargs):
                    return self._step("process", {"job_info": {"job_id": "stub-job-id"}})

            class StubAuthClient:
                fail = False

                def __init__(self, **kwargs):
                    pass

                def post_access_tokens(self):
                    print("auth progress")
                    if self.fail:
                        raise_for_status(unauthorized)
                    return {"access_token": "stub-access-token"}
            """,
            globals,
            globals,
        )
        original_client = QCIOpt.qcic.QciClient
        original_auth_client = QCIOpt.qcic.auth.client.AuthClient
        try
            client = globals["StubClient"]
            auth_client = globals["StubAuthClient"]
            QCIOpt.PythonCall.pysetattr(QCIOpt.qcic, "QciClient", client)
            QCIOpt.PythonCall.pysetattr(QCIOpt.qcic.auth.client, "AuthClient", auth_client)

            for silent in (false, true)
                displayed = _capture_stdout() do
                    @test QCIOpt.qci_get_allocations(; api_token = "offline-token", silent) ==
                          Dict("dirac" => Dict("paid" => false))
                    @test QCIOpt.qci_is_free_tier(; api_token = "offline-token", silent)
                    @test QCIOpt.qci_upload_file(qubo_file; api_token = "offline-token", silent) ==
                          "stub-file-id"
                    @test QCIOpt.qci_build_job_body(
                        QCIOpt.DIRAC_1{Float64}();
                        file_id = "stub-file-id",
                        api_token = "offline-token",
                        silent,
                    ) == Dict("job_submission" => Dict("stub" => true))
                    @test QCIOpt.qci_build_poly_job_body(
                        "stub-file-id";
                        api_token = "offline-token",
                        device_type = "dirac-3",
                        job_type = "sample-hamiltonian",
                        sum_constraint = 1.0,
                        silent,
                    ) == Dict("job_submission" => Dict("stub" => true))
                    @test QCIOpt.qci_process_job(
                        Dict("job_submission" => Dict("stub" => true));
                        api_token = "offline-token",
                        silent,
                    ) == Dict("job_info" => Dict("job_id" => "stub-job-id"))
                    @test QCIOpt.qci_auth_client(; api_token = "offline-token", silent) do c
                        c.post_access_tokens() |> QCIOpt.jl_object
                    end == Dict("access_token" => "stub-access-token")
                end
                normalized = replace(displayed, "\r\n" => "\n")
                expected_out = string(
                    "allocations progress\n",
                    "allocations progress\n",
                    "upload progress\n",
                    "build progress\n",
                    "build progress\n",
                    "process progress\n",
                    "auth progress\n",
                )
                @test normalized == (silent ? "" : expected_out)
            end

            client.fail = true
            auth_client.fail = true
            for silent in (false, true)
                local captured
                captured_stdout = _capture_stdout() do
                    captured = QCIOpt.qci_capture_client(; api_token = "offline-token", silent) do c
                        c.upload_file(; file = QCIOpt.py_object(qubo_file))
                    end
                end
                @test isnothing(captured.result)
                @test captured.error isa QCIOpt.QCI_UNAUTHORIZED_API_TOKEN_ERROR
                @test replace(captured.output[], "\r\n" => "\n") == "upload progress\n"
                @test replace(captured_stdout, "\r\n" => "\n") == (silent ? "" : "upload progress\n")

                local captured_auth
                captured_auth_stdout = _capture_stdout() do
                    captured_auth = QCIOpt.qci_capture_auth_client(; api_token = "offline-token", silent) do c
                        c.post_access_tokens()
                    end
                end
                @test isnothing(captured_auth.result)
                @test captured_auth.error isa QCIOpt.QCI_UNAUTHORIZED_API_TOKEN_ERROR
                @test replace(captured_auth.output[], "\r\n" => "\n") == "auth progress\n"
                @test replace(captured_auth_stdout, "\r\n" => "\n") == (silent ? "" : "auth progress\n")

                operations = (
                    ("allocations", () -> QCIOpt.qci_get_allocations(; api_token = "offline-token", silent)),
                    ("allocations", () -> QCIOpt.qci_is_free_tier(; api_token = "offline-token", silent)),
                    ("upload", () -> QCIOpt.qci_upload_file(qubo_file; api_token = "offline-token", silent)),
                    (
                        "build",
                        () -> QCIOpt.qci_build_job_body(
                            QCIOpt.DIRAC_1{Float64}();
                            file_id = "stub-file-id",
                            api_token = "offline-token",
                            silent,
                        ),
                    ),
                    (
                        "build",
                        () -> QCIOpt.qci_build_poly_job_body(
                            "stub-file-id";
                            api_token = "offline-token",
                            device_type = "dirac-3",
                            job_type = "sample-hamiltonian",
                            sum_constraint = 1.0,
                            silent,
                        ),
                    ),
                    (
                        "process",
                        () -> QCIOpt.qci_process_job(
                            Dict("job_submission" => Dict("stub" => true));
                            api_token = "offline-token",
                            silent,
                        ),
                    ),
                    (
                        "auth",
                        () -> QCIOpt.qci_auth_client(; api_token = "offline-token", silent) do c
                            c.post_access_tokens()
                        end,
                    ),
                )

                for (label, op) in operations
                    err_ref = Ref{Any}(nothing)
                    displayed = _capture_stdout() do
                        try
                            op()
                        catch err
                            err_ref[] = err
                        end
                    end
                    @test err_ref[] isa QCIOpt.QCI_UNAUTHORIZED_API_TOKEN_ERROR
                    normalized = replace(displayed, "\r\n" => "\n")
                    @test normalized == (silent ? "" : "$(label) progress\n")
                end
            end
        finally
            QCIOpt.PythonCall.pysetattr(QCIOpt.qcic, "QciClient", original_client)
            QCIOpt.PythonCall.pysetattr(QCIOpt.qcic.auth.client, "AuthClient", original_auth_client)
        end
    end
end
