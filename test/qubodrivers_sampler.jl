import QUBODrivers
import QUBODrivers: QUBOTools

function mock_dirac_backend_runner(
    matrix::AbstractMatrix{T};
    api_token,
    num_samples,
    relaxation_schedule,
    silent,
) where {T}
    @test api_token == "dummy-token"
    @test num_samples >= 1
    @test relaxation_schedule >= 1
    @test silent

    n = size(matrix, 1)
    state = zeros(Int, n)
    effective_ns = max(1, Int(num_samples))
    wall_end_ns = 1_000_000_000 + effective_ns

    return Dict{String,Any}(
        "response" => Dict{String,Any}(
            "status" => "COMPLETED",
            "results" => Dict{String,Any}(
                "solutions" => [state],
                "energies" => [Float64(state' * matrix * state)],
                "counts" => [Int(num_samples)],
            ),
            "job_info" => Dict{String,Any}(
                "job_id" => "mock-job-$(n)-$(num_samples)",
                "job_result" => Dict{String,Any}(
                    "device_usage_s" => effective_ns / 1e9,
                    "file_id" => "mock-result-file",
                ),
                "job_status" => Dict{String,Any}(
                    "submitted_at_rfc3339nano" => "2026-06-14T10:11:37.359Z",
                    "queued_at_rfc3339nano" => "2026-06-14T10:11:37.360Z",
                    "running_at_rfc3339nano" => "2026-06-14T10:11:37.879Z",
                    "completed_at_rfc3339nano" => "2026-06-14T10:11:38.879Z",
                ),
                "job_submission" => Dict{String,Any}(
                    "problem_config" => Dict{String,Any}(
                        "quadratic_unconstrained_binary_optimization" =>
                            Dict{String,Any}("qubo_file_id" => "mock-qubo-file"),
                    ),
                ),
            ),
        ),
        "metrics" => Dict{String,Any}(
            "job_id" => "mock-job-$(n)-$(num_samples)",
            "job_metrics" => Dict{String,Any}(
                "time_ns" => Dict{String,Any}(
                    "device" => Dict{String,Any}(
                        "dirac-1" => Dict{String,Any}(
                            "samples" => Dict{String,Any}(
                                "runtime" => ones(Int, Int(num_samples)),
                            ),
                        ),
                    ),
                    "wall" => Dict{String,Any}(
                        "start" => 1_000_000_000,
                        "end" => wall_end_ns,
                        "queue" => Dict{String,Any}(
                            "start" => 1_000_000_000,
                            "end" => 1_000_000_000,
                        ),
                        "processing" => Dict{String,Any}(
                            "start" => 1_000_000_000,
                            "end" => wall_end_ns,
                        ),
                    ),
                ),
            ),
        ),
        "qci_client_version" => "5.0.0",
        "request" => Dict{String,Any}("num_samples" => num_samples),
    )
end

function configure_mocked_dirac!(model)
    MOI.set(model, QCIOpt.DiracSampler.APIToken(), "dummy-token")
    MOI.set(model, QCIOpt.DiracSampler.Silent(), true)
    MOI.set(model, QCIOpt.DiracSampler.BackendRunner(), mock_dirac_backend_runner)

    return model
end

@testset "QUBODrivers DIRAC sampler" begin
    @testset "Attributes and QCI matrix conversion" begin
        sampler = QCIOpt.DiracSampler.Optimizer()

        @test MOI.get(sampler, MOI.SolverName()) == "QCI Dirac"
        @test MOI.get(sampler, QCIOpt.DiracSampler.NumberOfSamples()) == 10
        @test MOI.get(sampler, QCIOpt.DiracSampler.DeviceType()) == "dirac-1"
        @test !QUBODrivers.supports_seed(sampler)
        @test QUBODrivers.honors_final_reads(sampler)

        linear = Dict(1 => 1.0, 2 => 1.0)
        quadratic = Dict((1, 2) => -2.0)

        @test QCIOpt.DiracSampler.qci_qubo_matrix(Float64, 2, linear, quadratic, 1.0) ==
            [1.0 -1.0; -1.0 1.0]
    end

    @testset "Mocked sampler produces benchmark metadata" begin
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 2)

        MOI.add_constraint(model, x[1], MOI.ZeroOne())
        MOI.add_constraint(model, x[2], MOI.ZeroOne())

        f = MOI.ScalarQuadraticFunction(
            [MOI.ScalarQuadraticTerm(-2.0, x[1], x[2])],
            [MOI.ScalarAffineTerm(1.0, x[1]), MOI.ScalarAffineTerm(1.0, x[2])],
            1.0,
        )

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

        captured_matrix = Ref{Matrix{Float64}}()

        mock_runner = function (
            matrix;
            api_token,
            num_samples,
            relaxation_schedule,
            silent,
        )
            captured_matrix[] = copy(matrix)

            @test api_token == "dummy-token"
            @test num_samples == 5
            @test relaxation_schedule == 1
            @test silent

            return Dict{String,Any}(
                "response" => Dict{String,Any}(
                    "status" => "COMPLETED",
                    "results" => Dict{String,Any}(
                        "solutions" => [[0, 0], [0, 1], [1, 1]],
                        "energies" => [1.0, 2.0, 1.0],
                        "counts" => [1, 2, 2],
                    ),
                    "job_info" => Dict{String,Any}(
                        "job_id" => "job-123",
                        "job_result" => Dict{String,Any}(
                            "device_usage_s" => 2,
                            "file_id" => "result-file-123",
                        ),
                        "job_status" => Dict{String,Any}(
                            "submitted_at_rfc3339nano" => "2026-06-14T10:11:37.359Z",
                            "queued_at_rfc3339nano" => "2026-06-14T10:11:37.360Z",
                            "running_at_rfc3339nano" => "2026-06-14T10:11:37.879Z",
                            "completed_at_rfc3339nano" => "2026-06-14T10:13:51.189Z",
                        ),
                        "job_submission" => Dict{String,Any}(
                            "problem_config" => Dict{String,Any}(
                                "quadratic_unconstrained_binary_optimization" =>
                                    Dict{String,Any}("qubo_file_id" => "qubo-file-123"),
                            ),
                        ),
                    ),
                ),
                "metrics" => Dict{String,Any}(
                    "job_id" => "job-123",
                    "job_metrics" => Dict{String,Any}(
                        "time_ns" => Dict{String,Any}(
                            "device" => Dict{String,Any}(
                                "dirac-1" => Dict{String,Any}(
                                    "samples" => Dict{String,Any}(
                                        "runtime" => [
                                            100_000_000,
                                            200_000_000,
                                            300_000_000,
                                            400_000_000,
                                            500_000_000,
                                        ],
                                    ),
                                ),
                            ),
                            "wall" => Dict{String,Any}(
                                "start" => 1_000_000_000,
                                "end" => 4_000_000_000,
                                "queue" => Dict{String,Any}(
                                    "start" => 1_000_000_000,
                                    "end" => 1_500_000_000,
                                ),
                                "processing" => Dict{String,Any}(
                                    "start" => 1_500_000_000,
                                    "end" => 4_000_000_000,
                                ),
                            ),
                        ),
                    ),
                ),
                "qci_client_version" => "5.0.0",
                "request" => Dict{String,Any}("num_samples" => num_samples),
            )
        end

        sampler = QCIOpt.DiracSampler.Optimizer{Float64}()

        MOI.set(sampler, QCIOpt.DiracSampler.APIToken(), "dummy-token")
        MOI.set(sampler, QCIOpt.DiracSampler.NumberOfSamples(), 5)
        MOI.set(sampler, QCIOpt.DiracSampler.Silent(), true)
        MOI.set(sampler, QCIOpt.DiracSampler.BackendRunner(), mock_runner)

        MOI.copy_to(sampler, model)
        MOI.optimize!(sampler)

        @test captured_matrix[] == [1.0 -1.0; -1.0 1.0]
        @test MOI.get(sampler, MOI.ResultCount()) == 3
        @test MOI.get(sampler, MOI.RawStatusString()) == "COMPLETED"
        @test MOI.get(sampler, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        @test MOI.get(sampler, MOI.SolveTimeSec()) ≈ 1.5
        @test MOI.get(sampler, MOI.ObjectiveValue(1)) ≈ 1.0

        metadata = QUBOTools.metadata(QUBOTools.solution(sampler))

        @test isempty(QUBODrivers.validate_metadata(metadata))
        @test metadata["backend"]["name"] == "QCI Dirac"
        @test metadata["backend"]["version"] == "5.0.0"
        @test metadata["backend"]["device"] == "dirac-1"
        @test metadata["backend"]["job_id"] == "job-123"
        @test metadata["backend"]["result_file_id"] == "result-file-123"
        @test metadata["backend"]["problem_file_id"] == "qubo-file-123"
        @test metadata["reads"]["number_of_reads"] == 5
        @test metadata["reads"]["final_number_of_reads"] == 5
        @test metadata["time"]["effective"] ≈ 1.5
        @test metadata["time"]["provider_wall"] ≈ 3.0
        @test metadata["time"]["provider_queue"] ≈ 0.5
        @test metadata["time"]["provider_processing"] ≈ 2.5
        @test metadata["time"]["device_usage"] == 2
        @test metadata["provider"]["metrics"]["job_id"] == "job-123"
        @test metadata["provider"]["qci_client_version"] == "5.0.0"
    end

    @testset "QUBODrivers conformance suite with mocked backend" begin
        QUBODrivers.test(configure_mocked_dirac!, QCIOpt.DiracSampler.Optimizer)
    end
end
