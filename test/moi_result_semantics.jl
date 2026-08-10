@testset "MOI result-status and objective semantics" begin
    make_solution(samples, status) = QCIOpt.Solution{Float64,Float64}(
        samples,
        Dict{String,Any}("status" => status),
    )

    make_sample(point, value, reads) = QCIOpt.Sample{Float64,Float64}(point, value, reads)

    @testset "Provider status to MOI status mapping" begin
        # (provider status, has samples, expected termination status)
        status_table = [
            ("COMPLETED", true,  MOI.LOCALLY_SOLVED),
            ("CANCELLED", false, MOI.INTERRUPTED),
            ("ERRORED",   false, MOI.OTHER_ERROR),
            ("QUEUED",    false, MOI.OTHER_LIMIT),
            ("RUNNING",   false, MOI.OTHER_LIMIT),
            ("SUBMITTED", false, MOI.OTHER_LIMIT),
            ("SOME_FUTURE_STATUS", false, MOI.OTHER_ERROR),
        ]

        for (status, has_samples, termination) in status_table
            samples = if has_samples
                [make_sample([0.0, 1.0], 2.0, 3)]
            else
                QCIOpt.Sample{Float64,Float64}[]
            end

            solver = QCIOpt.Optimizer()
            solver.solution = make_solution(samples, status)

            @testset "$status" begin
                @test MOI.get(solver, MOI.TerminationStatus()) === termination
                @test MOI.get(solver, MOI.RawStatusString()) == status
                @test MOI.get(solver, MOI.ResultCount()) == length(samples)
                @test MOI.get(solver, MOI.DualStatus()) === MOI.NO_SOLUTION

                # PrimalStatus must be consistent with ResultCount: a feasible
                # point exists exactly when a sample backs the result index.
                if has_samples
                    @test MOI.get(solver, MOI.PrimalStatus()) === MOI.FEASIBLE_POINT
                else
                    @test MOI.get(solver, MOI.PrimalStatus()) === MOI.NO_SOLUTION
                end
            end
        end
    end

    @testset "Not yet optimized" begin
        solver = QCIOpt.Optimizer()

        @test MOI.get(solver, MOI.TerminationStatus()) === MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(solver, MOI.RawStatusString()) == "OPTIMIZE_NOT_CALLED"
        @test MOI.get(solver, MOI.ResultCount()) == 0
        @test MOI.get(solver, MOI.PrimalStatus()) === MOI.NO_SOLUTION
        @test MOI.get(solver, MOI.DualStatus()) === MOI.NO_SOLUTION
    end

    @testset "Result-index conventions" begin
        solver = QCIOpt.Optimizer()
        MOI.set(solver, QCIOpt.DeviceType(), "dirac-1")

        device = getfield(solver, :device)
        v1 = MOI.VariableIndex(1)
        v2 = MOI.VariableIndex(2)

        QCIOpt.var_map!(device.varmap, v1, 1)
        QCIOpt.var_map!(device.varmap, v2, 2)

        solver.solution = make_solution(
            [
                make_sample([0.0, 1.0], 1.5, 4),
                make_sample([1.0, 1.0], 2.5, 1),
            ],
            "COMPLETED",
        )

        @test MOI.get(solver, MOI.ResultCount()) == 2

        @test MOI.get(solver, MOI.ObjectiveValue(1)) ≈ 1.5
        @test MOI.get(solver, MOI.ObjectiveValue(2)) ≈ 2.5
        @test MOI.get(solver, MOI.VariablePrimal(1), v2) == 1.0
        @test MOI.get(solver, MOI.VariablePrimal(2), v1) == 1.0
        @test MOI.get(solver, QCIOpt.ResultMultiplicity(1)) == 4
        @test MOI.get(solver, QCIOpt.ResultMultiplicity(2)) == 1

        @test MOI.get(solver, MOI.PrimalStatus(2)) === MOI.FEASIBLE_POINT
        @test MOI.get(solver, MOI.PrimalStatus(3)) === MOI.NO_SOLUTION

        @test_throws MOI.ResultIndexBoundsError MOI.get(solver, MOI.ObjectiveValue(0))
        @test_throws MOI.ResultIndexBoundsError MOI.get(solver, MOI.ObjectiveValue(3))
        @test_throws MOI.ResultIndexBoundsError MOI.get(solver, MOI.VariablePrimal(3), v1)
        @test_throws MOI.ResultIndexBoundsError MOI.get(solver, QCIOpt.ResultMultiplicity(3))
    end

    # Objective table for f(x) = 1 + x₁ + x₂ - 2x₁x₂ over binary points:
    # f(0,0) = 1, f(1,0) = 2, f(0,1) = 2, f(1,1) = 1.
    @testset "DIRAC-1 objective semantics" begin
        function qubo_model(sense::MOI.OptimizationSense)
            model = MOI.Utilities.Model{Float64}()
            x = MOI.add_variables(model, 2)

            MOI.add_constraint(model, x[1], MOI.ZeroOne())
            MOI.add_constraint(model, x[2], MOI.ZeroOne())

            f = MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(-2.0, x[1], x[2])],
                [MOI.ScalarAffineTerm(1.0, x[1]), MOI.ScalarAffineTerm(1.0, x[2])],
                1.0,
            )

            MOI.set(model, MOI.ObjectiveSense(), sense)
            MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

            return model
        end

        @testset "Minimization" begin
            model = qubo_model(MOI.MIN_SENSE)
            solver = QCIOpt.Optimizer()
            MOI.set(solver, QCIOpt.DeviceType(), "dirac-1")

            device = getfield(solver, :device)

            QCIOpt.qci_load!(solver, device, model; api_token = "dummy-token")

            # The minimization form is the objective itself.
            @test device.matrix == [1.0 -1.0; -1.0 1.0]
            @test device.offset == 1.0

            samples = [
                make_sample([1.0, 0.0], 0.0, 1),
                make_sample([0.0, 0.0], 0.0, 2),
                make_sample([1.0, 1.0], 0.0, 3),
            ]
            adjusted = QCIOpt.readjust_qubo_values(device, samples, MOI.MIN_SENSE)

            # Best-first (ascending) with ties broken by multiplicity:
            # f(1,1) = 1 (3 reads), f(0,0) = 1 (2 reads), f(1,0) = 2.
            @test [s.value for s in adjusted] ≈ [1.0, 1.0, 2.0]
            @test adjusted[1].point == [1.0, 1.0]
            @test adjusted[2].point == [0.0, 0.0]
            @test adjusted[3].point == [1.0, 0.0]
        end

        @testset "Maximization" begin
            model = qubo_model(MOI.MAX_SENSE)
            solver = QCIOpt.Optimizer()
            MOI.set(solver, QCIOpt.DeviceType(), "dirac-1")

            device = getfield(solver, :device)

            QCIOpt.qci_load!(solver, device, model; api_token = "dummy-token")

            # The stored minimization form is the negated objective.
            @test device.matrix == [-1.0 1.0; 1.0 -1.0]
            @test device.offset == -1.0

            samples = [
                make_sample([1.0, 1.0], 0.0, 3),
                make_sample([1.0, 0.0], 0.0, 1),
                make_sample([0.0, 0.0], 0.0, 2),
            ]
            adjusted = QCIOpt.readjust_qubo_values(device, samples, MOI.MAX_SENSE)

            # Values are the original (un-negated) objective, ordered
            # best-first for maximization (descending):
            # f(1,0) = 2, f(1,1) = 1 (3 reads), f(0,0) = 1 (2 reads).
            @test [s.value for s in adjusted] ≈ [2.0, 1.0, 1.0]
            @test adjusted[1].point == [1.0, 0.0]
            @test adjusted[2].point == [1.0, 1.0]
            @test adjusted[3].point == [0.0, 0.0]
        end
    end

    # Objective table for f(x) = 1 + x₁ + x₂ - 2x₁x₂ over x ∈ {-1, 0, 1}²:
    # f(-1,-1) = -3, f(0,1) = 2, f(1,1) = 1 (matches the live DIRAC-3 IP test).
    @testset "DIRAC-3 objective semantics" begin
        function poly_model(sense::MOI.OptimizationSense)
            model = MOI.Utilities.Model{Float64}()
            x = MOI.add_variables(model, 2)

            for xi in x
                MOI.add_constraint(model, xi, MOI.Integer())
                MOI.add_constraint(model, xi, MOI.Interval(-1.0, 1.0))
            end

            f = MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(-2.0, x[1], x[2])],
                [MOI.ScalarAffineTerm(1.0, x[1]), MOI.ScalarAffineTerm(1.0, x[2])],
                1.0,
            )

            MOI.set(model, MOI.ObjectiveSense(), sense)
            MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

            return model
        end

        objective(x1, x2) = 1.0 + x1 + x2 - 2.0 * x1 * x2

        @testset "Load stores the minimization form" begin
            for (sense, factor) in [(MOI.MIN_SENSE, 1.0), (MOI.MAX_SENSE, -1.0)]
                model = poly_model(sense)
                solver = QCIOpt.Optimizer()

                device = getfield(solver, :device)
                @test device isa QCIOpt.DIRAC_3{Float64}

                vars = QCIOpt.qci_load!(solver, device, model)

                # The stored polynomial evaluates to (±1) × objective.
                for point in ([1.0, -1.0], [0.0, 1.0], [1.0, 1.0])
                    expected = factor * objective(point...)
                    @test device.poly(vars => point) ≈ expected
                end

                # Bounds were retrieved during the load.
                for vi in MOI.get(model, MOI.ListOfVariableIndices())
                    @test solver.lower[vi] == -1.0
                    @test solver.upper[vi] == 1.0
                end
            end
        end

        @testset "Result readjustment restores original values" begin
            for sense in (MOI.MIN_SENSE, MOI.MAX_SENSE)
                model = poly_model(sense)
                solver = QCIOpt.Optimizer()

                device = getfield(solver, :device)
                vars = QCIOpt.qci_load!(solver, device, model)

                # Provider points are shifted by the lower bound (-1), so the
                # provider point y maps back to x = y - 1.
                samples = [
                    make_sample([0.0, 0.0], 0.0, 1), # x = (-1, -1), f = -3
                    make_sample([1.0, 2.0], 0.0, 2), # x = (0, 1),   f = 2
                    make_sample([2.0, 2.0], 0.0, 3), # x = (1, 1),   f = 1
                ]

                adjusted = QCIOpt.readjust_poly_values(solver, device, vars, samples, sense)

                expected_values = if sense === MOI.MAX_SENSE
                    [2.0, 1.0, -3.0] # best-first: descending
                else
                    [-3.0, 1.0, 2.0] # best-first: ascending
                end

                @test [s.value for s in adjusted] ≈ expected_values

                if sense === MOI.MAX_SENSE
                    @test adjusted[1].point == [0.0, 1.0]
                    @test adjusted[3].point == [-1.0, -1.0]
                else
                    @test adjusted[1].point == [-1.0, -1.0]
                    @test adjusted[3].point == [0.0, 1.0]
                end
            end
        end
    end

    @testset "DiracSampler termination status stays consistent" begin
        @test QCIOpt.DiracSampler.termination_status("COMPLETED") === MOI.LOCALLY_SOLVED
        @test QCIOpt.DiracSampler.termination_status("CANCELLED") === MOI.INTERRUPTED
        @test QCIOpt.DiracSampler.termination_status("ERRORED") === MOI.OTHER_ERROR
        @test QCIOpt.DiracSampler.termination_status("QUEUED") === MOI.OTHER_LIMIT
        @test QCIOpt.DiracSampler.termination_status("RUNNING") === MOI.OTHER_LIMIT
        @test QCIOpt.DiracSampler.termination_status("SUBMITTED") === MOI.OTHER_LIMIT
        @test QCIOpt.DiracSampler.termination_status("SOME_FUTURE_STATUS") === MOI.OTHER_ERROR

        # Every provider status known to the MOI layer maps identically in the
        # QUBODrivers sampler path.
        for (status, code) in QCIOpt.QCI_TERMINATION_STATUS
            @test QCIOpt.DiracSampler.termination_status(status) === code
        end
    end
end
