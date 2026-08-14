function configured_job_optimizer(device_type::String)
    optimizer = QCIOpt.Optimizer()
    MOI.set(optimizer, QCIOpt.DeviceType(), device_type)
    MOI.set(optimizer, MOI.RawOptimizerAttribute("num_samples"), 7)
    if device_type == "dirac-3"
        MOI.set(optimizer, MOI.RawOptimizerAttribute("relaxation_schedule"), 4)
    end
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
                "job_name" => "",
                "job_tags" => String[],
            )
                attribute = MOI.RawOptimizerAttribute(name)
                @test MOI.supports(optimizer, attribute)
                @test MOI.get(optimizer, attribute) == default
            end

            relaxation_schedule =
                MOI.RawOptimizerAttribute("relaxation_schedule")
            if device_type == "dirac-3"
                @test MOI.supports(optimizer, relaxation_schedule)
                @test MOI.get(optimizer, relaxation_schedule) == 1
                sum_constraint = MOI.RawOptimizerAttribute("sum_constraint")
                @test MOI.supports(optimizer, sum_constraint)
                @test MOI.get(optimizer, sum_constraint) === nothing
            else
                @test !MOI.supports(optimizer, relaxation_schedule)
                @test_throws MOI.UnsupportedAttribute MOI.get(
                    optimizer,
                    relaxation_schedule,
                )
                @test !MOI.supports(
                    optimizer,
                    MOI.RawOptimizerAttribute("sum_constraint"),
                )
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
            optimizer.device;
            file_id = "offline-polynomial-file",
            num_levels = [2, 3],
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

            for boundary in (1, 100)
                MOI.set(
                    optimizer,
                    MOI.RawOptimizerAttribute("num_samples"),
                    boundary,
                )
                @test MOI.get(
                    optimizer,
                    MOI.RawOptimizerAttribute("num_samples"),
                ) == boundary
            end

            for value in (0, 101, 1.5, true)
                error = raw_attribute_error(optimizer, "num_samples", value)
                @test error isa ArgumentError
                @test occursin("num_samples", sprint(showerror, error))
                @test occursin("1:100", sprint(showerror, error))
            end

            for (name, value) in (
                ("job_name", nothing),
                ("job_name", 39),
                ("job_tags", "offline"),
                ("job_tags", ["offline", 39]),
            )
                error = raw_attribute_error(optimizer, name, value)
                @test error isa ArgumentError
                @test occursin(name, sprint(showerror, error))
            end

            relaxation_schedule =
                MOI.RawOptimizerAttribute("relaxation_schedule")
            if device_type == "dirac-3"
                for boundary in (1, 4)
                    MOI.set(optimizer, relaxation_schedule, boundary)
                    @test MOI.get(optimizer, relaxation_schedule) == boundary
                end

                for value in (0, 5, 2.5, false)
                    error = raw_attribute_error(
                        optimizer,
                        "relaxation_schedule",
                        value,
                    )
                    @test error isa ArgumentError
                    @test occursin(
                        "relaxation_schedule",
                        sprint(showerror, error),
                    )
                    @test occursin("1:4", sprint(showerror, error))
                end

                sum_constraint = MOI.RawOptimizerAttribute("sum_constraint")
                for boundary in (1, 10_000, 2.5)
                    MOI.set(optimizer, sum_constraint, boundary)
                    @test MOI.get(optimizer, sum_constraint) == boundary
                end

                MOI.set(
                    optimizer,
                    MOI.RawOptimizerAttribute("num_samples"),
                    42,
                )
                clear_error = raw_attribute_error(
                    optimizer,
                    "sum_constraint",
                    nothing,
                )
                @test clear_error === nothing
                if isnothing(clear_error)
                    @test MOI.get(optimizer, sum_constraint) === nothing
                    @test MOI.get(
                        optimizer,
                        MOI.RawOptimizerAttribute("num_samples"),
                    ) == 42
                end

                for value in (0, 10_001, Inf, NaN, true, "2")
                    error = raw_attribute_error(optimizer, "sum_constraint", value)
                    @test error isa ArgumentError
                    @test occursin("sum_constraint", sprint(showerror, error))
                    @test occursin("[1, 10000]", sprint(showerror, error))
                end
            else
                @test_throws MOI.UnsupportedAttribute MOI.set(
                    optimizer,
                    relaxation_schedule,
                    1,
                )
                @test_throws MOI.UnsupportedAttribute MOI.set(
                    optimizer,
                    MOI.RawOptimizerAttribute("sum_constraint"),
                    2,
                )
            end

            unsupported =
                MOI.RawOptimizerAttribute("arbitrary_provider_option")
            @test_throws MOI.UnsupportedAttribute MOI.set(
                optimizer,
                unsupported,
                "silently dropped before issue 39",
            )
            @test_throws MOI.UnsupportedAttribute MOI.get(
                optimizer,
                unsupported,
            )
        end
    end
end
