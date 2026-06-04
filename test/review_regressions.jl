@testset "Review regressions" begin
    @testset "Device selection updates dispatch target" begin
        optimizer = QCIOpt.Optimizer()

        MOI.set(optimizer, QCIOpt.DeviceType(), "dirac-1")

        @test MOI.get(optimizer, QCIOpt.DeviceType()) == "dirac-1"
        @test getfield(optimizer, :device) isa QCIOpt.DIRAC_1{Float64}
        @test MOI.is_empty(optimizer)

        MOI.set(optimizer, QCIOpt.DeviceType(), "dirac-3")

        @test MOI.get(optimizer, QCIOpt.DeviceType()) == "dirac-3"
        @test getfield(optimizer, :device) isa QCIOpt.DIRAC_3{Float64}
    end

    @testset "Raw silent attribute" begin
        optimizer = QCIOpt.Optimizer()
        attr = MOI.RawOptimizerAttribute("silent")

        @test MOI.supports(optimizer, attr)

        MOI.set(optimizer, attr, true)

        @test MOI.get(optimizer, attr)
    end

    @testset "Client wrapper captures stdout" begin
        response = QCIOpt.qci_client_wrapper(:client; silent = true) do client
            @test client === :client
            print("provider output")

            return 42
        end

        @test response.result == 42
        @test response.output[] == "provider output"
        @test isnothing(response.error)
    end

    @testset "DIRAC-1 QUBO loading helpers" begin
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

        @test QCIOpt.assert_is_qubo_model(model) === nothing
    end

    @testset "DIRAC-1 result readjustment" begin
        device = QCIOpt.DIRAC_1{Float64}()
        v1 = MOI.VariableIndex(1)
        v2 = MOI.VariableIndex(2)

        QCIOpt.var_map!(device.varmap, v1, 1)
        QCIOpt.var_map!(device.varmap, v2, 2)

        device.matrix = [1.0 0.0; 0.0 1.0]
        device.offset = 1.0

        samples = [QCIOpt.Sample{Float64,Float64}([0.0, 1.0], 0.0, 2)]
        adjusted = QCIOpt.readjust_qubo_values(device, samples, MOI.MIN_SENSE)

        @test length(adjusted) == 1
        @test adjusted[1].point == [0.0, 1.0]
        @test adjusted[1].value ≈ 2.0
        @test adjusted[1].reads == 2
    end

    @testset "Solve time metadata" begin
        status = Dict(
            "running_at_rfc3339nano" => "2026-06-04T10:00:00Z",
            "completed_at_rfc3339nano" => "2026-06-04T10:00:03Z",
        )

        @test QCIOpt.qci_get_elapsed_time(status) == 3.0
    end
end
