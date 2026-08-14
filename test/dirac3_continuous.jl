@testset "DIRAC-3 continuous simplex contract" begin
    function continuous_model(;
        sense = MOI.MIN_SENSE,
        lower = (0.0, 0.0),
        upper = (nothing, nothing),
        integer = (false, false),
        fixed = (nothing, nothing),
    )
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 2)

        for (i, xi) in enumerate(x)
            isnothing(lower[i]) || MOI.add_constraint(model, xi, MOI.GreaterThan(lower[i]))
            isnothing(upper[i]) || MOI.add_constraint(model, xi, MOI.LessThan(upper[i]))
            integer[i] && MOI.add_constraint(model, xi, MOI.Integer())
            isnothing(fixed[i]) || MOI.add_constraint(model, xi, MOI.EqualTo(fixed[i]))
        end

        # (x₁ - 0.5)² + (x₂ - 1.5)², whose independent optimum on
        # x₁ + x₂ = 2, x >= 0 is (0.5, 1.5) with value zero.
        f = MOI.ScalarQuadraticFunction(
            [
                MOI.ScalarQuadraticTerm(2.0, x[1], x[1]),
                MOI.ScalarQuadraticTerm(2.0, x[2], x[2]),
            ],
            [
                MOI.ScalarAffineTerm(-1.0, x[1]),
                MOI.ScalarAffineTerm(-3.0, x[2]),
            ],
            2.5,
        )

        MOI.set(model, MOI.ObjectiveSense(), sense)
        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

        return model
    end

    function load_continuous(model = continuous_model(); sum_constraint = 2.0)
        solver = QCIOpt.Optimizer()
        isnothing(sum_constraint) || MOI.set(
            solver,
            MOI.RawOptimizerAttribute("sum_constraint"),
            sum_constraint,
        )
        device = solver.device
        vars = QCIOpt.qci_load!(solver, device, model)

        return (; solver, device, vars)
    end

    @testset "Production request selects the normalized-qudit simplex" begin
        (; solver, device, vars) = load_continuous()
        request = QCIOpt.qci_build_poly_request(solver, device, vars)

        @test request.job_type == "sample-hamiltonian"
        @test request.sum_constraint == 2.0
        @test request.num_levels === nothing
        @test request.poly == device.poly

        config = request.file["file_config"]["polynomial"]
        @test config["num_variables"] == 2
        @test Dict(entry["idx"] => entry["val"] for entry in config["data"]) == Dict(
            [1, 1] => 1.0,
            [2, 2] => 1.0,
            [0, 1] => -1.0,
            [0, 2] => -3.0,
        )

        body = QCIOpt.qci_build_poly_job_body(
            solver,
            device;
            file_id = "offline-continuous-polynomial",
            num_levels = request.num_levels,
            sum_constraint = request.sum_constraint,
            api_token = "offline-token",
            silent = true,
        )
        submission = body["job_submission"]

        @test submission["problem_config"] == Dict{String,Any}(
            "normalized_qudit_hamiltonian_optimization" => Dict{String,Any}(
                "polynomial_file_id" => "offline-continuous-polynomial",
            ),
        )
        @test submission["device_config"] == Dict{String,Any}(
            "dirac-3_normalized_qudit" => Dict{String,Any}(
                "num_samples" => 10,
                "relaxation_schedule" => 1,
                "sum_constraint" => 2.0,
            ),
        )
        @test !occursin("offline-token", repr(body))

        for kwargs in (NamedTuple(), (; num_levels = [2, 2], sum_constraint = 2.0))
            error = try
                QCIOpt.qci_build_poly_job_body(
                    solver,
                    device;
                    file_id = "invalid-domain-parameters",
                    api_token = "offline-token",
                    silent = true,
                    kwargs...,
                )
                nothing
            catch error
                error
            end
            @test error isa ErrorException
            @test occursin("requires exactly one domain parameter", sprint(showerror, error))
        end
    end

    @testset "Returned samples already use model coordinates" begin
        for sense in (MOI.MIN_SENSE, MOI.MAX_SENSE)
            model = continuous_model(; sense)
            (; solver, device, vars) = load_continuous(model)
            provider_samples = [
                QCIOpt.Sample{Float64,Float64}([1.0, 1.0], -2.0, 2),
                QCIOpt.Sample{Float64,Float64}([0.5, 1.5], -2.5, 3),
            ]

            adjusted = QCIOpt.readjust_poly_values(
                solver,
                device,
                vars,
                provider_samples,
                sense,
            )

            expected_points = if sense === MOI.MIN_SENSE
                [[0.5, 1.5], [1.0, 1.0]]
            else
                [[1.0, 1.0], [0.5, 1.5]]
            end
            expected_values = sense === MOI.MIN_SENSE ? [0.0, 0.5] : [0.5, 0.0]

            @test [sample.point for sample in adjusted] == expected_points
            @test [sample.value for sample in adjusted] ≈ expected_values

            solution = QCIOpt.Solution{Float64,Float64}(
                provider_samples,
                Dict{String,Any}("status" => "COMPLETED"),
            )
            @test QCIOpt.qci_store_results!(solver, device, model, vars, solution) === nothing
            @test MOI.get(solver, MOI.ObjectiveValue(1)) ≈ first(expected_values)
            @test MOI.get(solver, MOI.VariablePrimal(1), MOI.VariableIndex(1)) ==
                  first(expected_points)[1]
        end
    end

    @testset "Unsupported domains fail before network access" begin
        cases = [
            (
                "missing sum constraint",
                continuous_model(),
                nothing,
                "require the raw optimizer attribute",
            ),
            (
                "missing nonnegative bound",
                continuous_model(; lower = (nothing, 0.0)),
                2.0,
                "must have lower bound 0",
            ),
            (
                "nonzero lower bound",
                continuous_model(; lower = (0.25, 0.0)),
                2.0,
                "must have lower bound 0",
            ),
            (
                "box upper bound",
                continuous_model(; upper = (2.0, nothing)),
                2.0,
                "does not accept per-variable boxes",
            ),
            (
                "mixed integer and continuous",
                continuous_model(; integer = (true, false)),
                2.0,
                "cannot mix integer/fixed and continuous",
            ),
            (
                "mixed fixed and continuous",
                continuous_model(; lower = (nothing, 0.0), fixed = (0.5, nothing)),
                2.0,
                "cannot mix integer/fixed and continuous",
            ),
        ]

        for (name, model, resource, fragment) in cases
            @testset "$name" begin
                (; solver, device, vars) = load_continuous(model; sum_constraint = resource)

                error = try
                    QCIOpt.qci_build_poly_request(solver, device, vars)
                    nothing
                catch error
                    error
                end

                @test error isa ErrorException
                @test occursin(fragment, sprint(showerror, error))
            end
        end

        (; solver, device, vars) = load_continuous(
            continuous_model(; integer = (true, true));
            sum_constraint = 2.0,
        )
        error = try
            QCIOpt.qci_build_poly_request(solver, device, vars)
            nothing
        catch error
            error
        end
        @test error isa ErrorException
        @test occursin("Unset `sum_constraint` for integer jobs", sprint(showerror, error))

        with_qci_token(nothing) do
            model = continuous_model()
            solver = QCIOpt.Optimizer()
            MOI.set(solver, MOI.RawOptimizerAttribute("api_token"), "not-a-valid-token")
            MOI.set(solver, MOI.Silent(), true)

            error = try
                MOI.optimize!(solver, model)
                nothing
            catch error
                error
            end

            @test error isa ErrorException
            @test occursin("sum_constraint", sprint(showerror, error))
        end
    end
end
