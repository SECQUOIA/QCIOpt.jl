using Test
using JuMP
using QCIOpt

function main()
    @testset "QCIOpt Tests" begin
        @testset "Authentication" begin
            @test QCIOpt.__auth__()
            
            if QCIOpt.qci_is_free_tier()
                @info "Running in QCI Free Tier"
            end
        end

        @testset "DIRAC-1 ■ QUBO" begin
            let model = Model(QCIOpt.Optimizer)
                table = Dict(
                    [0, 0] => 1,
                    [0, 1] => 2,
                    [1, 0] => 2,
                    [1, 1] => 1,
                )

                @variable(model, x[1:2], Bin)

                @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2]) # x[1] ⊻ x[2]

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

        @testset "DIRAC-3 ■ QUBO" begin
            let model = Model(QCIOpt.Optimizer)
                table = Dict(
                    [0, 0] => 1,
                    [0, 1] => 2,
                    [1, 0] => 2,
                    [1, 1] => 1,
                )

                @variable(model, x[1:2], Bin)

                @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2]) # x[1] ⊻ x[2]

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

        @testset "DIRAC-3 ■ IP" begin
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

                # set_silent(model)

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

    return nothing
end

main() # Here we go!
