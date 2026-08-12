@testset "Provider metadata in the MOI solve path" begin
    # Fixtures follow the QCI client contract: `process_job` returns `job_info`,
    # `status`, and `results` (`nothing` unless the job COMPLETED), and a
    # submission records its input file under a problem-type-keyed
    # `problem_config` — `qubo_file_id` under
    # `quadratic_unconstrained_binary_optimization` for DIRAC-1 `sample-qubo`
    # jobs, and `polynomial_file_id` under `qudit_hamiltonian_optimization` for
    # DIRAC-3 `sample-hamiltonian-integer` jobs.

    # Timestamps 0.5 s apart from submitted to queued, then 0.5 s to running,
    # then 1.0 s to completed: queue = 0.5, run = 1.0, total = 2.0.
    job_status_fixture() = Dict{String,Any}(
        "submitted_at_rfc3339nano" => "2026-06-14T10:11:37.359Z",
        "queued_at_rfc3339nano"    => "2026-06-14T10:11:37.859Z",
        "running_at_rfc3339nano"   => "2026-06-14T10:11:38.359Z",
        "completed_at_rfc3339nano" => "2026-06-14T10:11:39.359Z",
    )

    completed_qubo_response() = Dict{String,Any}(
        "status" => "COMPLETED",
        "results" => Dict{String,Any}(
            "solutions" => [[1, 1], [1, 0], [0, 0]],
            "energies"  => [-1.0, 0.0, 0.0],
            "counts"    => [3, 1, 2],
        ),
        "job_info" => Dict{String,Any}(
            "job_id" => "job-qubo-1",
            "job_result" => Dict{String,Any}(
                "file_id"        => "result-file-qubo",
                "device_usage_s" => 0.75,
            ),
            "job_status" => job_status_fixture(),
            "job_submission" => Dict{String,Any}(
                "problem_config" => Dict{String,Any}(
                    "quadratic_unconstrained_binary_optimization" =>
                        Dict{String,Any}("qubo_file_id" => "qubo-file-1"),
                ),
                "device_config" => Dict{String,Any}(
                    "dirac-1" => Dict{String,Any}("num_samples" => 6),
                ),
            ),
        ),
    )

    completed_poly_response() = Dict{String,Any}(
        "status" => "COMPLETED",
        "results" => Dict{String,Any}(
            # Provider points are shifted by the lower bound (-1), so y maps to
            # x = y - 1: (0, 1), (-1, -1), and (1, 1).
            "solutions" => [[1, 2], [0, 0], [2, 2]],
            "energies"  => [0.0, 0.0, 0.0],
            "counts"    => [2, 1, 3],
        ),
        "job_info" => Dict{String,Any}(
            "job_id" => "job-poly-3",
            "job_result" => Dict{String,Any}(
                "file_id"        => "result-file-poly",
                "device_usage_s" => 1.25,
            ),
            "job_status" => job_status_fixture(),
            "job_submission" => Dict{String,Any}(
                "problem_config" => Dict{String,Any}(
                    "qudit_hamiltonian_optimization" =>
                        Dict{String,Any}("polynomial_file_id" => "poly-file-3"),
                ),
                "device_config" => Dict{String,Any}(
                    "dirac-3_qudit" => Dict{String,Any}("num_levels" => [3, 3]),
                ),
            ),
        ),
    )

    # An errored job never completes, so it carries a partial `job_status` — no
    # `completed_at_` timestamp — and no result file. The queue time it did
    # reach is still reported.
    function errored_response(; job_result = Dict{String,Any}("error" => "device allocation exhausted"))
        job_info = Dict{String,Any}(
            "job_id" => "job-errored",
            "job_status" => Dict{String,Any}(
                "submitted_at_rfc3339nano" => "2026-06-14T10:11:37.359Z",
                "queued_at_rfc3339nano"    => "2026-06-14T10:11:37.859Z",
                "running_at_rfc3339nano"   => "2026-06-14T10:11:38.359Z",
            ),
        )

        if !isnothing(job_result)
            job_info["job_result"] = job_result
        end

        return Dict{String,Any}(
            "status"   => "ERRORED",
            "results"  => nothing,
            "job_info" => job_info,
        )
    end

    # f(x) = 1 + x₁ + x₂ - 2x₁x₂, as in test/moi_result_semantics.jl.
    function objective_function(x)
        return MOI.ScalarQuadraticFunction(
            [MOI.ScalarQuadraticTerm(-2.0, x[1], x[2])],
            [MOI.ScalarAffineTerm(1.0, x[1]), MOI.ScalarAffineTerm(1.0, x[2])],
            1.0,
        )
    end

    function qubo_model()
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 2)

        MOI.add_constraint(model, x[1], MOI.ZeroOne())
        MOI.add_constraint(model, x[2], MOI.ZeroOne())

        f = objective_function(x)

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

        return model
    end

    function poly_model()
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 2)

        for xi in x
            MOI.add_constraint(model, xi, MOI.Integer())
            MOI.add_constraint(model, xi, MOI.Interval(-1.0, 1.0))
        end

        f = objective_function(x)

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

        return model
    end

    # Both device paths, loaded and stored offline: `qci_parse_results` and
    # `qci_store_results!` are the whole network-free result path.
    function qubo_solver(solution)
        model = qubo_model()
        solver = QCIOpt.Optimizer()

        MOI.set(solver, QCIOpt.DeviceType(), "dirac-1")

        device = getfield(solver, :device)

        QCIOpt.qci_load!(solver, device, model; api_token = "dummy-token")
        QCIOpt.qci_store_results!(solver, device, model, solution)

        return solver
    end

    function poly_solver(solution)
        model = poly_model()
        solver = QCIOpt.Optimizer()

        device = getfield(solver, :device)
        vars = QCIOpt.qci_load!(solver, device, model)

        QCIOpt.qci_store_results!(solver, device, model, vars, solution)

        return solver
    end

    parse_response(response) = QCIOpt.qci_parse_results(Float64, Float64, response)

    metadata_keys = (
        "status",
        "job_id",
        "result_file_id",
        "problem_file_id",
        "queue_time_sec",
        "run_time_sec",
        "total_time_sec",
        "device_usage_sec",
        "error",
        "response",
    )

    @testset "Completed job on both device paths" begin
        cases = [
            ("DIRAC-1", completed_qubo_response, qubo_solver, "qubo-file-1", "result-file-qubo", 0.75, 1.0),
            ("DIRAC-3", completed_poly_response, poly_solver, "poly-file-3", "result-file-poly", 1.25, -3.0),
        ]

        for (label, make_response, make_solver, problem_file_id, result_file_id, device_usage, best_value) in cases
            @testset "$label" begin
                response = make_response()
                solver = make_solver(parse_response(response))

                # The response is preserved verbatim as the solution metadata.
                @test solver.solution.metadata === response

                @test MOI.get(solver, MOI.RawStatusString()) == "COMPLETED"
                @test MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
                @test MOI.get(solver, MOI.ResultCount()) == 3
                @test MOI.get(solver, MOI.ObjectiveValue(1)) ≈ best_value
                @test MOI.get(solver, MOI.SolveTimeSec()) ≈ 1.0

                metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

                @test issetequal(keys(metadata), metadata_keys)
                @test metadata["status"] == "COMPLETED"
                @test metadata["job_id"] == QCIOpt.qci_response_field(response, "job_info", "job_id")
                @test metadata["result_file_id"] == result_file_id
                @test metadata["problem_file_id"] == problem_file_id
                @test metadata["queue_time_sec"] ≈ 0.5
                @test metadata["run_time_sec"] ≈ 1.0
                @test metadata["total_time_sec"] ≈ 2.0
                @test metadata["device_usage_sec"] == device_usage
                @test isnothing(metadata["error"])
                @test metadata["response"] === response

                # `MOI.SolveTimeSec` and the metadata report the same duration.
                @test metadata["run_time_sec"] ≈ MOI.get(solver, MOI.SolveTimeSec())
            end
        end
    end

    @testset "Errored job on both device paths" begin
        for (label, make_solver) in [("DIRAC-1", qubo_solver), ("DIRAC-3", poly_solver)]
            @testset "$label" begin
                response = errored_response()

                # The provider diagnostic is surfaced, not swallowed.
                solution = @test_logs (:error, "device allocation exhausted") parse_response(response)

                solver = make_solver(solution)

                @test solver.solution.metadata === response

                @test MOI.get(solver, MOI.RawStatusString()) == "ERRORED"
                @test MOI.get(solver, MOI.TerminationStatus()) === MOI.OTHER_ERROR
                @test MOI.get(solver, MOI.ResultCount()) == 0
                @test MOI.get(solver, MOI.PrimalStatus()) === MOI.NO_SOLUTION
                @test isnan(MOI.get(solver, MOI.SolveTimeSec()))

                @test_throws MOI.ResultIndexBoundsError MOI.get(solver, MOI.ObjectiveValue(1))

                metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

                @test metadata["status"] == "ERRORED"
                @test metadata["job_id"] == "job-errored"
                @test metadata["error"] == "device allocation exhausted"

                # The job never ran and produced no files, so those fields are
                # absent rather than fabricated — and the queue time it does
                # report is still readable.
                @test isnothing(metadata["result_file_id"])
                @test isnothing(metadata["problem_file_id"])
                @test isnothing(metadata["run_time_sec"])
                @test isnothing(metadata["total_time_sec"])
                @test isnothing(metadata["device_usage_sec"])
                @test metadata["queue_time_sec"] ≈ 0.5
            end
        end
    end

    @testset "Errored job without a provider diagnostic" begin
        # A missing `job_info.job_result.error` must not mask the ERRORED status
        # by failing the parse.
        for job_result in (nothing, Dict{String,Any}(), Dict{String,Any}("file_id" => "partial"))
            response = errored_response(; job_result)

            solution = @test_logs(
                (:error, "QCI reported an ERRORED job without a job-error message."),
                parse_response(response),
            )

            solver = qubo_solver(solution)
            metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

            @test MOI.get(solver, MOI.RawStatusString()) == "ERRORED"
            @test MOI.get(solver, MOI.TerminationStatus()) === MOI.OTHER_ERROR
            @test metadata["status"] == "ERRORED"
            @test isnothing(metadata["error"])
        end
    end

    @testset "Missing optional provider fields" begin
        @testset "No job_info at all" begin
            response = Dict{String,Any}(
                "status"  => "COMPLETED",
                "results" => Dict{String,Any}(
                    "solutions" => [[1, 1], [1, 0], [0, 0]],
                    "energies"  => [-1.0, 0.0, 0.0],
                    "counts"    => [3, 1, 2],
                ),
            )

            solver = qubo_solver(parse_response(response))

            # Every result-side `MOI.get` still works.
            @test MOI.get(solver, MOI.RawStatusString()) == "COMPLETED"
            @test MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
            @test MOI.get(solver, MOI.ResultCount()) == 3
            @test MOI.get(solver, MOI.PrimalStatus()) === MOI.FEASIBLE_POINT
            @test MOI.get(solver, MOI.ObjectiveValue(1)) ≈ 1.0
            @test MOI.get(solver, MOI.VariablePrimal(1), MOI.VariableIndex(1)) == 1.0
            @test MOI.get(solver, QCIOpt.ResultMultiplicity(1)) == 3

            # Timing is unknown rather than an error.
            @test isnan(MOI.get(solver, MOI.SolveTimeSec()))

            metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

            @test metadata["status"] == "COMPLETED"
            @test metadata["response"] === response

            for key in metadata_keys
                key in ("status", "response") && continue

                @test isnothing(metadata[key])
            end
        end

        @testset "Partial job_status" begin
            # Completed, but the provider reported no completion timestamp: the
            # queue time it did report stays readable.
            response = completed_qubo_response()

            delete!(response["job_info"]["job_status"], "completed_at_rfc3339nano")

            solver = qubo_solver(parse_response(response))
            metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

            @test MOI.get(solver, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
            @test isnan(MOI.get(solver, MOI.SolveTimeSec()))
            @test isnothing(metadata["run_time_sec"])
            @test isnothing(metadata["total_time_sec"])
            @test metadata["queue_time_sec"] ≈ 0.5
            @test metadata["job_id"] == "job-qubo-1"
        end

        @testset "Empty job_result" begin
            response = completed_qubo_response()

            response["job_info"]["job_result"] = Dict{String,Any}()

            solver = qubo_solver(parse_response(response))
            metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

            @test isnothing(metadata["result_file_id"])
            @test isnothing(metadata["device_usage_sec"])
            @test isnothing(metadata["error"])
            @test metadata["problem_file_id"] == "qubo-file-1"
            @test MOI.get(solver, MOI.SolveTimeSec()) ≈ 1.0
        end
    end

    @testset "Metadata without a provider status" begin
        solver = QCIOpt.Optimizer()
        solver.solution = QCIOpt.Solution{Float64,Float64}(
            QCIOpt.Sample{Float64,Float64}[],
            Dict{String,Any}("job_info" => Dict{String,Any}("job_id" => "job-partial")),
        )

        @test MOI.get(solver, MOI.RawStatusString()) == QCIOpt.QCI_UNKNOWN_STATUS
        @test MOI.get(solver, MOI.TerminationStatus()) === MOI.OTHER_ERROR
        @test isnan(MOI.get(solver, MOI.SolveTimeSec()))

        metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

        @test isnothing(metadata["status"])
        @test metadata["job_id"] == "job-partial"
    end

    @testset "Before the first solve" begin
        solver = QCIOpt.Optimizer()
        metadata = MOI.get(solver, QCIOpt.ProviderMetadata())

        @test issetequal(keys(metadata), metadata_keys)
        @test isempty(metadata["response"])

        for key in metadata_keys
            key == "response" && continue

            @test isnothing(metadata[key])
        end

        @test MOI.get(solver, MOI.RawStatusString()) == "OPTIMIZE_NOT_CALLED"
        @test isnan(MOI.get(solver, MOI.SolveTimeSec()))
    end

    @testset "Completed responses that violate the results contract" begin
        for (label, mutate!, needle) in [
            ("no results payload", res -> (res["results"] = nothing), "carries no 'results'"),
            ("missing counts", res -> delete!(res["results"], "counts"), "missing 'counts'"),
            (
                "length mismatch",
                res -> (res["results"]["counts"] = [1, 2]),
                "disagree on length",
            ),
        ]
            @testset "$label" begin
                response = completed_qubo_response()

                mutate!(response)

                err = try
                    parse_response(response)
                    nothing
                catch err
                    err
                end

                @test err isa ErrorException
                @test occursin(needle, sprint(showerror, err))
                # The reported status is named, not masked.
                @test occursin("COMPLETED", sprint(showerror, err))
            end
        end
    end

    @testset "Provider field extraction" begin
        @testset "Nested field reads" begin
            response = completed_qubo_response()

            @test QCIOpt.qci_response_field(response, "status") == "COMPLETED"
            @test QCIOpt.qci_response_field(response, "job_info", "job_id") == "job-qubo-1"
            @test isnothing(QCIOpt.qci_response_field(response, "job_info", "absent"))
            @test isnothing(QCIOpt.qci_response_field(response, "absent", "job_id"))
            # A non-dictionary partway through the path is not indexed into.
            @test isnothing(QCIOpt.qci_response_field(response, "status", "job_id"))
            @test isnothing(QCIOpt.qci_response_field(nothing, "status"))
        end

        @testset "Problem file id for both job types" begin
            @test QCIOpt.qci_problem_file_id(completed_qubo_response()) == "qubo-file-1"
            @test QCIOpt.qci_problem_file_id(completed_poly_response()) == "poly-file-3"
            @test isnothing(QCIOpt.qci_problem_file_id(errored_response()))

            # The client's deprecated spelling of the polynomial file id.
            deprecated = completed_poly_response()
            deprecated["job_info"]["job_submission"]["problem_config"] = Dict{String,Any}(
                "qudit_hamiltonian_optimization" =>
                    Dict{String,Any}("hamiltonian_file_id" => "hamiltonian-file-3"),
            )

            @test QCIOpt.qci_problem_file_id(deprecated) == "hamiltonian-file-3"
        end

        @testset "Ambiguous problem config resolves deterministically" begin
            # A submission carries exactly one problem type. Should a response
            # ever carry several, the id must not fall out of `Dict` iteration
            # order: the documented tie-break is the alphabetically first
            # problem type, here `ising_...` ahead of `quadratic_...` and
            # `qudit_...`.
            ambiguous = Dict{String,Any}(
                "job_info" => Dict{String,Any}(
                    "job_submission" => Dict{String,Any}(
                        "problem_config" => Dict{String,Any}(
                            "qudit_hamiltonian_optimization" =>
                                Dict{String,Any}("polynomial_file_id" => "qudit-file"),
                            "quadratic_unconstrained_binary_optimization" =>
                                Dict{String,Any}("qubo_file_id" => "qubo-file"),
                            "ising_hamiltonian_optimization" =>
                                Dict{String,Any}("polynomial_file_id" => "ising-file"),
                        ),
                    ),
                ),
            )

            @test QCIOpt.qci_problem_file_id(ambiguous) == "ising-file"
        end

        @testset "Timestamp parsing" begin
            # `rfc3339nano` keys can carry more precision than `DateTime` holds.
            nanos = Dict{String,Any}(
                "running_at_rfc3339nano"   => "2026-06-14T10:11:38.123456789Z",
                "completed_at_rfc3339nano" => "2026-06-14T10:11:39.123456789Z",
            )

            @test QCIOpt.qci_get_elapsed_time(nanos) ≈ 1.0

            # A trailing Z is optional, and whole seconds parse.
            @test QCIOpt.qci_get_elapsed_time(
                Dict{String,Any}(
                    "running_at_rfc3339nano"   => "2026-06-14T10:11:38",
                    "completed_at_rfc3339nano" => "2026-06-14T10:11:41",
                ),
            ) ≈ 3.0

            # An explicit UTC offset is refused rather than read as if it were
            # UTC, which would silently shift a duration by whole hours.
            @test isnan(
                QCIOpt.qci_get_elapsed_time(
                    Dict{String,Any}(
                        "running_at_rfc3339nano"   => "2026-06-14T10:11:38.359+02:00",
                        "completed_at_rfc3339nano" => "2026-06-14T10:11:39.359+02:00",
                    ),
                ),
            )

            # Ambiguous, unparseable, backwards, and non-string timestamps.
            @test isnan(
                QCIOpt.qci_get_elapsed_time(
                    Dict{String,Any}(
                        "running_at_rfc3339nano" => "2026-06-14T10:11:38.359Z",
                        "running_at_legacy"      => "2026-06-14T10:11:38.359Z",
                        "completed_at_rfc3339nano" => "2026-06-14T10:11:39.359Z",
                    ),
                ),
            )
            @test isnan(
                QCIOpt.qci_get_elapsed_time(
                    Dict{String,Any}(
                        "running_at_rfc3339nano"   => "yesterday",
                        "completed_at_rfc3339nano" => "2026-06-14T10:11:39.359Z",
                    ),
                ),
            )
            @test isnan(
                QCIOpt.qci_get_elapsed_time(
                    Dict{String,Any}(
                        "running_at_rfc3339nano"   => "2026-06-14T10:11:40.359Z",
                        "completed_at_rfc3339nano" => "2026-06-14T10:11:39.359Z",
                    ),
                ),
            )
            @test isnan(
                QCIOpt.qci_get_elapsed_time(
                    Dict{String,Any}(
                        "running_at_rfc3339nano"   => 1_000_000_000,
                        "completed_at_rfc3339nano" => 2_000_000_000,
                    ),
                ),
            )
            @test isnan(QCIOpt.qci_get_elapsed_time(nothing))

            @test isnothing(QCIOpt.qci_parse_timestamp("2026-06-14"))
            @test QCIOpt.qci_parse_timestamp("2026-06-14T10:11:38.359Z") ==
                QCIOpt.Dates.DateTime(2026, 6, 14, 10, 11, 38, 359)
        end
    end

    @testset "Documented JuMP access" begin
        # The README and API reference read the attribute through JuMP on a
        # plain `Model`, which wraps the optimizer in a `CachingOptimizer`; that
        # maps every optimizer-attribute value it returns through `map_indices`,
        # so a `Dict` value needs an explicit pass-through method to be readable
        # at all. Reading it before a solve is enough to exercise that path.
        @testset "Model" begin
            model = Model(QCIOpt.Optimizer)
            metadata = get_attribute(model, QCIOpt.ProviderMetadata())

            @test metadata isa Dict{String,Any}
            @test issetequal(keys(metadata), metadata_keys)
            @test isnothing(metadata["status"])
        end

        # `direct_model` reaches the optimizer with no caching layer, so it can
        # also be checked against a stored response.
        @testset "direct_model" begin
            response = completed_qubo_response()
            model = direct_model(QCIOpt.Optimizer())

            set_attribute(model, QCIOpt.DeviceType(), "dirac-1")

            solver = backend(model)
            device = getfield(solver, :device)

            QCIOpt.qci_load!(solver, device, qubo_model(); api_token = "dummy-token")
            QCIOpt.qci_store_results!(
                solver,
                device,
                qubo_model(),
                parse_response(response),
            )

            metadata = get_attribute(model, QCIOpt.ProviderMetadata())

            @test metadata["status"] == "COMPLETED"
            @test metadata["job_id"] == "job-qubo-1"
            @test metadata["result_file_id"] == "result-file-qubo"
            @test metadata["problem_file_id"] == "qubo-file-1"
            @test metadata["run_time_sec"] ≈ 1.0
            @test metadata["response"] === response
        end
    end

    @testset "Documented contract covers every metadata key" begin
        api_reference = replace(
            read(joinpath(dirname(@__DIR__), "docs", "src", "api.md"), String),
            "\r\n" => "\n",
        )

        # Keep the searched document out of the assertions: a failure renderer
        # that expands the whole API reference buries the missing key.
        documents(needle) = occursin(needle, api_reference)

        for key in metadata_keys
            @test documents("\"$(key)\"")
        end

        # The relationship to the QUBODrivers sampler metadata from #25.
        @test documents("DiracSampler")
        @test documents("ProviderMetadata")
    end
end
