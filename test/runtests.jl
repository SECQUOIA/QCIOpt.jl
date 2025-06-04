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
                @variable(model, x[1:3], Bin)

                @objective(model, Min, sum((-1) ^ (i + j) * x[i] * x[j] for i = 1:3 for j = 1:3))

                set_attribute(model, QCIOpt.DeviceType(), "dirac-1")

                # set_silent(model)

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = value.(x; result = i)
                        @test length(xi) == 3
                        @test all(ξ -> ξ == 0 || ξ == 1, xi)
                    end

                    @test objective_value(model; result = i) ≈ 0.0
                    @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end

        @testset "DIRAC-3 ■ IP" begin
            let model = Model(QCIOpt.Optimizer)
                @variable(model, -10 <= x[1:3] <= 10, Int)

                @objective(model, Min, sum((-1) ^ (i + j) * x[i] * x[j] for i = 1:3 for j = 1:3))

                set_attribute(model, QCIOpt.DeviceType(), "dirac-3")

                # set_silent(model)

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = value.(x; result = i)
                        @test length(xi) == 3
                        @test all(ξ -> -10 <= ξ <= 10, xi)
                    end

                    @test objective_value(model; result = i) ≈ 400.0
                    @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end
    end

    return nothing
end

main() # Here we go!
