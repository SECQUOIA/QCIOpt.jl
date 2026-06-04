@testset "Offline optimizer surface" begin
    with_qci_token(nothing) do
        @test !QCIOpt.__auth__()

        @test QCIOpt.qci_supported_devices() == ["dirac-1", "dirac-3"]
        @test QCIOpt.qci_supports_device("dirac-1")
        @test QCIOpt.qci_supports_device("dirac-3")
        @test !QCIOpt.qci_supports_device("dirac-2")
        @test QCIOpt.qci_device("dirac-1") isa QCIOpt.DIRAC_1
        @test QCIOpt.qci_device("dirac-3") isa QCIOpt.DIRAC_3

        optimizer = QCIOpt.Optimizer()

        @test MOI.is_empty(optimizer)
        @test MOI.supports(optimizer, QCIOpt.DeviceType())
        @test MOI.supports(optimizer, MOI.Silent())
        @test MOI.supports(optimizer, MOI.RawOptimizerAttribute("api_token"))
        @test MOI.supports(optimizer, MOI.RawOptimizerAttribute("num_samples"))
        @test MOI.get(optimizer, QCIOpt.DeviceType()) == "dirac-3"
        @test MOI.get(optimizer, MOI.RawOptimizerAttribute("api_token")) === nothing

        MOI.set(optimizer, MOI.RawOptimizerAttribute("api_token"), "local-token")
        @test MOI.get(optimizer, MOI.RawOptimizerAttribute("api_token")) == "local-token"

        MOI.set(optimizer, MOI.Silent(), true)
        @test MOI.get(optimizer, MOI.Silent())

        MOI.set(optimizer, QCIOpt.DeviceType(), "dirac-1")
        @test MOI.get(optimizer, QCIOpt.DeviceType()) == "dirac-1"
        @test MOI.get(optimizer, MOI.RawOptimizerAttribute("num_samples")) == 10

        model = Model(QCIOpt.Optimizer)
        @variable(model, x[1:2], Bin)
        @objective(model, Min, 1 + x[1] + x[2] - 2 * x[1] * x[2])
        set_attribute(model, QCIOpt.DeviceType(), "dirac-1")
        set_attribute(model, MOI.RawOptimizerAttribute("num_samples"), 5)
        set_silent(model)

        @test num_variables(model) == 2

        qubo_file = QCIOpt.qci_data_file([1.0 0.5; 0.5 2.0])
        @test qubo_file["file_name"] == "smallest_objective.json"
        @test haskey(qubo_file["file_config"], "qubo")
        @test haskey(qubo_file["file_config"]["qubo"], "data")

        poly_file = QCIOpt.qci_data_file([[1, 0], [1, 2]], [1.5, -2.0])
        poly = poly_file["file_config"]["polynomial"]

        @test poly_file["file_name"] == ""
        @test poly["num_variables"] == 2
        @test poly["min_degree"] == 1
        @test poly["max_degree"] == 2
        @test poly["data"] == [
            Dict{String,Any}("idx" => [1, 0], "val" => 1.5),
            Dict{String,Any}("idx" => [1, 2], "val" => -2.0),
        ]
    end
end

@testset "Missing token optimize error" begin
    with_qci_token(nothing) do
        @test !QCIOpt.__auth__()

        model = Model(QCIOpt.Optimizer)
        @variable(model, x[1:2], Bin)
        @objective(model, Min, x[1] + x[2])

        err = try
            optimize!(model)
            nothing
        catch err
            err
        end

        @test err isa ErrorException
        @test occursin("QCI API Token is not defined.", sprint(showerror, err))
    end
end
