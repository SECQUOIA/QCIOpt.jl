using Test
using JuMP
using QCIOpt

function main()
    @testset "QCIOpt Tests" begin
        @testset "Authentication" begin
            @test QCIOpt.__auth__()
        end

        @testset "Simple Model" begin
            let model = Model(QCIOpt.Optimizer)
                @variable(model, -10 <= x[1:3] <= 10, Int)

                @objective(model, Min, sum((-1) ^ (i + j) * x[i] * x[j] for i = 1:3 for j = 1:3))

                # set_silent(model)

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    @test length(value.(x; result = i)) == 3
                    @test objective_value(model; result = i) >= 400.0
                    @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end
    end

    return nothing
end

main() # Here we go!
