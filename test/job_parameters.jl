function configured_job_optimizer(device_type::String)
    optimizer = QCIOpt.Optimizer()
    MOI.set(optimizer, QCIOpt.DeviceType(), device_type)
    MOI.set(optimizer, MOI.RawOptimizerAttribute("num_samples"), 7)
    MOI.set(optimizer, MOI.RawOptimizerAttribute("relaxation_schedule"), 4)
    MOI.set(optimizer, MOI.RawOptimizerAttribute("job_name"), "issue-39-contract")
    MOI.set(
        optimizer,
        MOI.RawOptimizerAttribute("job_tags"),
        ["offline", "boundary-test"],
    )
    return optimizer
end

function raw_attribute_error(optimizer, name::String, value)
    return try
        MOI.set(optimizer, MOI.RawOptimizerAttribute(name), value)
        nothing
    catch error
        error
    end
end

@testset "QCI job-parameter contract" begin
    @testset "Supported names and defaults" begin
        for device_type in ("dirac-1", "dirac-3")
            optimizer = QCIOpt.Optimizer()
            MOI.set(optimizer, QCIOpt.DeviceType(), device_type)

            for (name, default) in (
                "num_samples" => 10,
                "relaxation_schedule" => 1,
                "job_name" => "",
                "job_tags" => String[],
            )
                attribute = MOI.RawOptimizerAttribute(name)
                @test MOI.supports(optimizer, attribute)
                @test MOI.get(optimizer, attribute) == default
            end
        end
    end

    @testset "DIRAC-1 caller-to-builder boundary" begin
        optimizer = configured_job_optimizer("dirac-1")
        body = QCIOpt.qci_build_job_body(
            optimizer,
            optimizer.device;
            file_id = "offline-qubo-file",
            api_token = "offline-token",
            silent = true,
        )
        submission = body["job_submission"]

        @test submission["job_name"] == "issue-39-contract"
        @test submission["job_tags"] == ["offline", "boundary-test"]
        @test submission["device_config"] == Dict{String,Any}(
            "dirac-1" => Dict{String,Any}(
                "num_samples" => 7,
                "relaxation_schedule" => 4,
            ),
        )
        @test submission["problem_config"] == Dict{String,Any}(
            "quadratic_unconstrained_binary_optimization" =>
                Dict{String,Any}("qubo_file_id" => "offline-qubo-file"),
        )
        @test !occursin("offline-token", repr(body))
    end

    @testset "DIRAC-3 caller-to-builder boundary" begin
        optimizer = configured_job_optimizer("dirac-3")
        body = QCIOpt.qci_build_poly_job_body(
            optimizer,
            optimizer.device,
            "offline-polynomial-file",
            [2, 3];
            api_token = "offline-token",
            silent = true,
        )
        submission = body["job_submission"]

        @test submission["job_name"] == "issue-39-contract"
        @test submission["job_tags"] == ["offline", "boundary-test"]
        @test submission["device_config"] == Dict{String,Any}(
            "dirac-3_qudit" => Dict{String,Any}(
                "num_samples" => 7,
                "num_levels" => [2, 3],
                "relaxation_schedule" => 4,
            ),
        )
        @test submission["problem_config"] == Dict{String,Any}(
            "qudit_hamiltonian_optimization" => Dict{String,Any}(
                "polynomial_file_id" => "offline-polynomial-file",
            ),
        )
        @test !occursin("offline-token", repr(body))
    end

    @testset "Invalid and unsupported values fail at the MOI boundary" begin
        for device_type in ("dirac-1", "dirac-3")
            optimizer = QCIOpt.Optimizer()
            MOI.set(optimizer, QCIOpt.DeviceType(), device_type)

            for (name, value) in (
                ("num_samples", 0),
                ("num_samples", 1.5),
                ("num_samples", true),
                ("relaxation_schedule", -1),
                ("relaxation_schedule", 2.5),
                ("relaxation_schedule", false),
                ("job_name", nothing),
                ("job_name", 39),
                ("job_tags", "offline"),
                ("job_tags", ["offline", 39]),
            )
                error = raw_attribute_error(optimizer, name, value)
                @test error isa ArgumentError
                @test occursin(name, sprint(showerror, error))
            end

            @test_throws MOI.UnsupportedAttribute MOI.set(
                optimizer,
                MOI.RawOptimizerAttribute("arbitrary_provider_option"),
                "silently dropped before issue 39",
            )
        end
    end
end
