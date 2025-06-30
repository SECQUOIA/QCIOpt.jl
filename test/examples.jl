function test_examples()
    @testset "▶ Examples" verbose = true begin
        # @testset "DIRAC-1 ■ QUBO" begin
        #     let model = Model(QCIOpt.Optimizer)
        #         table = Dict(
        #             [0, 0] => 1,
        #             [0, 1] => 2,
        #             [1, 0] => 2,
        #             [1, 1] => 1,
        #         )

        #         @variable(model, x[1:2], Bin)

        #         @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2]) # x[1] ⊻ x[2]

        #         set_attribute(model, QCIOpt.DeviceType(), "dirac-1")

        #         optimize!(model)

        #         @test result_count(model) >= 1

        #         for i = 1:result_count(model)
        #             let xi = round.(Int, value.(x; result = i))
        #                 @test length(xi) == 2
        #                 @test objective_value(model; result = i) ≈ table[xi]
        #             end

        #             @test MOI.get(model, QCIOpt.ResultMultiplicity(i)) >= 1
        #         end
        #     end
        # end # DIRAC-1 ■ QUBO

        @testset "DIRAC-3 ■ QUBO" begin
            let model = Model(QCIOpt.Optimizer)
                table = Dict(
                    [0, 0] => 1,
                    [0, 1] => 2,
                    [1, 0] => 2,
                    [1, 1] => 1,
                )

                @variable(model, x[1:2], Bin)

                @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2]) # 1 + x[1] ⊻ x[2]

                set_attribute(model, QCIOpt.DeviceType(), "dirac-3")

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = round.(Int, value.(x; result = i))
                        @test length(xi) == 2
                        @test objective_value(model; result = i) ≈ table[xi]
                    end

                    @test get_attribute(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end # DIRAC-3 ■ QUBO

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

                optimize!(model)

                @test result_count(model) >= 1

                for i = 1:result_count(model)
                    let xi = round.(Int, value.(x; result = i))
                        @test length(xi) == 2
                        @test objective_value(model; result = i) ≈ table[xi]
                    end

                    @test get_attribute(model, QCIOpt.ResultMultiplicity(i)) >= 1
                end
            end
        end # DIRAC-3 ■ IP
    end # Examples

    return nothing
end
