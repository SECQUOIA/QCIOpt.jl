using Test
using JuMP
using QCIOpt

import QUBODrivers
import QUBODrivers: QUBOTools

if QCIOpt.__auth__()
    @testset "Live QCI service smoke tests" begin
        @testset "DIRAC-1 QUBO" begin
            let model = Model(QCIOpt.Optimizer)
                table = Dict(
                    [0, 0] => 1,
                    [0, 1] => 2,
                    [1, 0] => 2,
                    [1, 1] => 1,
                )

                @variable(model, x[1:2], Bin)

                @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2])

                set_attribute(model, QCIOpt.DeviceType(), "dirac-1")

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = round.(Int, value.(x; result = i))
                        @test length(xi) == 2
                        @test objective_value(model; result = i) ≈ table[xi]
                    end

                    @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end

        @testset "DIRAC-1 QUBODrivers metadata" begin
            model = MOI.Utilities.Model{Float64}()
            x = MOI.add_variables(model, 2)

            MOI.add_constraint(model, x[1], MOI.ZeroOne())
            MOI.add_constraint(model, x[2], MOI.ZeroOne())

            f = MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(-2.0, x[1], x[2])],
                [MOI.ScalarAffineTerm(1.0, x[1]), MOI.ScalarAffineTerm(1.0, x[2])],
                1.0,
            )

            sampler = QCIOpt.DiracSampler.Optimizer{Float64}()

            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(model, MOI.ObjectiveFunction{typeof(f)}(), f)
            MOI.set(sampler, QCIOpt.DiracSampler.NumberOfSamples(), 5)
            MOI.set(sampler, QCIOpt.DiracSampler.Silent(), true)

            MOI.copy_to(sampler, model)
            MOI.optimize!(sampler)

            sampleset = QUBOTools.solution(sampler)
            metadata = QUBOTools.metadata(sampleset)
            violations = QUBODrivers.validate_metadata(sampleset)

            @test isempty(violations)
            @test metadata["backend"]["device"] == "dirac-1"
            @test metadata["backend"]["job_id"] isa AbstractString
            @test metadata["time"]["effective"] > 0
            @test metadata["provider"]["metrics"] isa AbstractDict

            println("LIVE_QCI_QUBODRIVERS_METADATA_BEGIN")
            show(stdout, MIME("text/plain"), metadata)
            println()
            println("LIVE_QCI_QUBODRIVERS_METADATA_END")
        end

        @testset "DIRAC-3 QUBO" begin
            let model = Model(QCIOpt.Optimizer)
                table = Dict(
                    [0, 0] => 1,
                    [0, 1] => 2,
                    [1, 0] => 2,
                    [1, 1] => 1,
                )

                @variable(model, x[1:2], Bin)

                @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2])

                set_attribute(model, QCIOpt.DeviceType(), "dirac-3")

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = round.(Int, value.(x; result = i))
                        @test length(xi) == 2
                        @test objective_value(model; result = i) ≈ table[xi]
                    end

                    @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end

        @testset "DIRAC-3 IP" begin
            let model = Model(QCIOpt.Optimizer)
                table = Dict(
                    [-1, -1] => -3,
                    [-1,  0] =>  0,
                    [-1,  1] =>  3,
                    [ 0, -1] =>  0,
                    [ 0,  0] =>  1,
                    [ 0,  1] =>  2,
                    [ 1, -1] =>  3,
                    [ 1,  0] =>  2,
                    [ 1,  1] =>  1,
                )

                @variable(model, -1 <= x[1:2] <= 1, Int)

                @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2])

                set_attribute(model, QCIOpt.DeviceType(), "dirac-3")

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = round.(Int, value.(x; result = i))
                        @test length(xi) == 2
                        @test objective_value(model; result = i) ≈ table[xi]
                    end

                    @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end
    end
else
    @info "Skipping live QCI service smoke tests because QCI_TOKEN is not set."
end
