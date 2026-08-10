@testset "DIRAC-3 variable-bounds transformation contract" begin
    # Every testset below uses unequal, nonzero bounds so that a wrong shift
    # direction, a per-vector instead of per-element filter, or a lower bound
    # read from a different source than the levels cannot cancel out:
    #
    #   x₁ ∈ [-3, -1] (Int), x₂ ∈ [2, 5] (Int)
    #   f(x) = 2 + 3x₁ - x₂ + 4x₁x₂
    #
    # Substituting x₁ ↦ y₁ - 3 and x₂ ↦ y₂ + 2 gives, by hand,
    #
    #   q(y) = 2 + 3(y₁ - 3) - (y₂ + 2) + 4(y₁ - 3)(y₂ + 2)
    #        = -33 + 11y₁ - 13y₂ + 4y₁y₂
    #
    # over y₁ ∈ {0, 1, 2} and y₂ ∈ {0, 1, 2, 3}.
    objective(x1, x2) = 2.0 + 3.0 * x1 - x2 + 4.0 * x1 * x2

    function bounded_model(;
        sense = MOI.MIN_SENSE,
        lower = (-3.0, 2.0),
        upper = (-1.0, 5.0),
        integer = true,
        bounded = true,
    )
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 2)

        for (i, xi) in enumerate(x)
            integer && MOI.add_constraint(model, xi, MOI.Integer())
            bounded && MOI.add_constraint(model, xi, MOI.Interval(lower[i], upper[i]))
        end

        f = MOI.ScalarQuadraticFunction(
            [MOI.ScalarQuadraticTerm(4.0, x[1], x[2])],
            [MOI.ScalarAffineTerm(3.0, x[1]), MOI.ScalarAffineTerm(-1.0, x[2])],
            2.0,
        )

        MOI.set(model, MOI.ObjectiveSense(), sense)
        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

        return model
    end

    # Load a model and return everything the transformation contract needs.
    function load(model)
        solver = QCIOpt.Optimizer()
        device = getfield(solver, :device)
        vars = QCIOpt.qci_load!(solver, device, model)

        return (; solver, device, vars)
    end

    # The polynomial actually submitted to the device.
    function submitted(solver, device, vars)
        domains = QCIOpt.variable_domains(solver, device, vars)

        return QCIOpt.rescale_variables(device.poly, vars, Float64[li for (li, _) in domains])
    end

    x_grid = [(x1, x2) for x1 in -3:-1 for x2 in 2:5]
    y_grid = [(y1, y2) for y1 in 0:2 for y2 in 0:3]

    @testset "Transformed domains and levels" begin
        (; solver, device, vars) = load(bounded_model())

        @test QCIOpt.variable_domains(solver, device, vars) == [(-3, -1), (2, 5)]
        @test QCIOpt.get_levels(solver, device, vars) == [3, 4]
    end

    @testset "Submitted polynomial is p(y + l)" begin
        (; solver, device, vars) = load(bounded_model())

        poly = submitted(solver, device, vars)

        # Independently derived above: q(y) = -33 + 11y₁ - 13y₂ + 4y₁y₂.
        @test poly ==
              -33.0 + 11.0 * vars[1] - 13.0 * vars[2] + 4.0 * vars[1] * vars[2]

        # The contract, stated directly: the value the device sees at y is the
        # model's objective at the point y maps back to.
        for (y1, y2) in y_grid
            @test poly(vars => [Float64(y1), Float64(y2)]) ≈ objective(y1 - 3, y2 + 2)
        end
    end

    @testset "Submitted minimizer maps back to the model minimizer" begin
        # The device minimizes the submitted polynomial over the level grid, so
        # a shift in the wrong direction sends it over a region the model never
        # contained and the mapped-back point is not the model's optimum. This
        # is the failure a live DIRAC-3 run exhibited (issue #41).
        (; solver, device, vars) = load(bounded_model())

        poly = submitted(solver, device, vars)

        best_y = argmin(y -> poly(vars => [Float64(y[1]), Float64(y[2])]), y_grid)
        best_x = argmin(x -> objective(x...), x_grid)

        @test (best_y[1] - 3, best_y[2] + 2) == best_x

        # Every level point maps into the model's own domain.
        for (y1, y2) in y_grid
            @test (y1 - 3, y2 + 2) ∈ x_grid
        end
    end

    @testset "Request construction" begin
        (; solver, device, vars) = load(bounded_model())

        poly = submitted(solver, device, vars)

        file = QCIOpt.qci_data_file(
            xi -> QCIOpt.var_idx(device.varmap, QCIOpt.var_inv(device.varmap, xi)),
            poly,
        )
        config = file["file_config"]["polynomial"]

        @test config["num_variables"] == 2
        @test config["min_degree"] == 1
        @test config["max_degree"] == 2

        # Terms of q, padded to the maximum degree and indexed by the model's
        # variable order. The constant -33 is dropped by the file writer;
        # `readjust_poly_values` recomputes objective values from the stored
        # polynomial, so a reported objective value never misses it.
        @test Dict(entry["idx"] => entry["val"] for entry in config["data"]) == Dict(
            [0, 1] => 11.0,
            [0, 2] => -13.0,
            [1, 2] => 4.0,
        )

        @test QCIOpt.get_levels(solver, device, vars) == [3, 4]
    end

    @testset "Returned sample and objective reconstruction" begin
        # Provider points on the level grid, deliberately not best-first, with
        # objective values computed by hand:
        #   y = (0, 0) → x = (-3, 2), f = 2 - 9 - 2 - 24 = -33
        #   y = (2, 3) → x = (-1, 5), f = 2 - 3 - 5 - 20 = -26
        #   y = (1, 1) → x = (-2, 3), f = 2 - 6 - 3 - 24 = -31
        provider_samples() = [
            QCIOpt.Sample{Float64,Float64}([0.0, 0.0], 0.0, 1),
            QCIOpt.Sample{Float64,Float64}([2.0, 3.0], 0.0, 2),
            QCIOpt.Sample{Float64,Float64}([1.0, 1.0], 0.0, 3),
        ]

        # (sense, points best-first, values best-first, multiplicities)
        expectations = [
            (MOI.MIN_SENSE, [[-3.0, 2.0], [-2.0, 3.0], [-1.0, 5.0]], [-33.0, -31.0, -26.0], [1, 3, 2]),
            (MOI.MAX_SENSE, [[-1.0, 5.0], [-2.0, 3.0], [-3.0, 2.0]], [-26.0, -31.0, -33.0], [2, 3, 1]),
        ]

        for (sense, points, values, reads) in expectations
            @testset "$sense" begin
                model = bounded_model(; sense)
                (; solver, device, vars) = load(model)

                adjusted =
                    QCIOpt.readjust_poly_values(solver, device, vars, provider_samples(), sense)

                @test [s.point for s in adjusted] == points
                @test [s.value for s in adjusted] ≈ values
                @test [s.reads for s in adjusted] == reads

                # The same values reach the public MOI surface through the
                # model-sense handoff.
                solution = QCIOpt.Solution{Float64,Float64}(
                    provider_samples(),
                    Dict{String,Any}("status" => "COMPLETED"),
                )

                @test QCIOpt.qci_store_results!(solver, device, model, vars, solution) === nothing
                @test MOI.get(solver, MOI.ObjectiveValue(1)) ≈ first(values)
                @test MOI.get(solver, MOI.VariablePrimal(1), MOI.VariableIndex(1)) == first(points)[1]
            end
        end
    end

    @testset "Integer variables with fractional bounds use the integer lattice" begin
        # x₁ ∈ [-2.5, -1.0] ∩ ℤ = {-2, -1}: the shift and the level count must
        # both use ceil(-2.5) = -2, or the mapped-back points are not integers.
        (; solver, device, vars) = load(bounded_model(; lower = (-2.5, 2.0)))

        @test QCIOpt.variable_domains(solver, device, vars) == [(-2, -1), (2, 5)]
        @test QCIOpt.get_levels(solver, device, vars) == [2, 4]

        poly = submitted(solver, device, vars)

        for y1 in 0:1, y2 in 0:3
            @test poly(vars => [Float64(y1), Float64(y2)]) ≈ objective(y1 - 2, y2 + 2)
        end

        samples = [QCIOpt.Sample{Float64,Float64}([1.0, 0.0], 0.0, 1)]
        adjusted =
            QCIOpt.readjust_poly_values(solver, device, vars, samples, MOI.MIN_SENSE)

        @test adjusted[1].point == [-1.0, 2.0]
        @test adjusted[1].value ≈ objective(-1, 2)
    end

    @testset "Variables already starting at zero are left alone" begin
        # `l = (0, 2)`: the first variable needs no shift, the second does, so
        # a mixed bound vector still transforms each variable by its own bound.
        (; solver, device, vars) = load(bounded_model(; lower = (0.0, 2.0), upper = (2.0, 5.0)))

        poly = submitted(solver, device, vars)

        for y1 in 0:2, y2 in 0:3
            @test poly(vars => [Float64(y1), Float64(y2)]) ≈ objective(y1, y2 + 2)
        end

        # All-zero lower bounds submit the objective unchanged.
        (; solver, device, vars) = load(bounded_model(; lower = (0.0, 0.0), upper = (2.0, 3.0)))

        @test submitted(solver, device, vars) == device.poly
    end

    @testset "Bounds from several constraints are intersected" begin
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 3)

        # A binary variable additionally capped below one.
        MOI.add_constraint(model, x[1], MOI.ZeroOne())
        MOI.add_constraint(model, x[1], MOI.LessThan(0.0))

        # A binary variable inside a wider interval.
        MOI.add_constraint(model, x[2], MOI.ZeroOne())
        MOI.add_constraint(model, x[2], MOI.Interval(-1.0, 5.0))

        # Separate lower and upper bounds.
        MOI.add_constraint(model, x[3], MOI.Integer())
        MOI.add_constraint(model, x[3], MOI.GreaterThan(1.0))
        MOI.add_constraint(model, x[3], MOI.LessThan(4.0))

        solver = QCIOpt.Optimizer()

        QCIOpt.retrieve_variable_bounds!(solver, model)

        @test (solver.lower[x[1]], solver.upper[x[1]]) == (0.0, 0.0)
        @test (solver.lower[x[2]], solver.upper[x[2]]) == (0.0, 1.0)
        @test (solver.lower[x[3]], solver.upper[x[3]]) == (1.0, 4.0)

        @test solver.integral == Set(x)
    end

    @testset "Unsupported and invalid domains fail with actionable errors" begin
        # (name, model, expected message fragment)
        cases = [
            (
                "continuous variable",
                bounded_model(; integer = false),
                "samples integer-valued variables only",
            ),
            (
                "missing bounds",
                bounded_model(; bounded = false),
                "is missing a lower bound",
            ),
            (
                "infinite bound",
                bounded_model(; lower = (-Inf, 2.0)),
                "is bounded by [-Inf, -1.0]",
            ),
            (
                "no integer point",
                bounded_model(; lower = (-2.8, 2.0), upper = (-2.2, 5.0)),
                "contains no integer point",
            ),
        ]

        for (name, model, fragment) in cases
            @testset "$name" begin
                (; solver, device, vars) = load(model)

                err = try
                    QCIOpt.variable_domains(solver, device, vars)
                    nothing
                catch err
                    err
                end

                @test err isa ErrorException
                @test occursin(fragment, sprint(showerror, err))
            end
        end

        @testset "level budget" begin
            @test QCIOpt.assert_level_budget([250, 250], 500) === nothing

            err = try
                QCIOpt.assert_level_budget([300, 201], 500)
                nothing
            catch err
                err
            end

            @test err isa ErrorException
            @test occursin("501 DIRAC-3 levels across 2 variables", sprint(showerror, err))
            @test occursin("500-level budget", sprint(showerror, err))
        end
    end

    @testset "Fixed variables span a single level" begin
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variables(model, 2)

        # Pinned outright, with no integrality declaration.
        MOI.add_constraint(model, x[1], MOI.EqualTo(2.0))
        MOI.add_constraint(model, x[2], MOI.Integer())
        MOI.add_constraint(model, x[2], MOI.Interval(1.0, 3.0))

        f = MOI.ScalarAffineFunction(
            [MOI.ScalarAffineTerm(1.0, x[1]), MOI.ScalarAffineTerm(1.0, x[2])],
            0.0,
        )

        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)

        (; solver, device, vars) = load(model)

        @test QCIOpt.variable_domains(solver, device, vars) == [(2, 2), (1, 3)]
        @test QCIOpt.get_levels(solver, device, vars) == [1, 3]

        samples = [QCIOpt.Sample{Float64,Float64}([0.0, 2.0], 0.0, 1)]
        adjusted =
            QCIOpt.readjust_poly_values(solver, device, vars, samples, MOI.MIN_SENSE)

        @test adjusted[1].point == [2.0, 3.0]
        @test adjusted[1].value ≈ 5.0
    end

    @testset "Solver state tracks integrality" begin
        solver = QCIOpt.Optimizer()

        @test MOI.is_empty(solver)

        (; solver, device, vars) = load(bounded_model())

        @test !MOI.is_empty(solver)
        @test length(solver.integral) == 2

        MOI.empty!(solver)

        @test isempty(solver.integral)
        @test MOI.is_empty(solver)
    end
end
