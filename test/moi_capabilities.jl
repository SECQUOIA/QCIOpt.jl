@testset "MOI capability and silent-output contract" begin
    @testset "Device-specific objective support" begin
        objective_rows = [
            (MOI.VariableIndex, false, true),
            (MOI.ScalarAffineFunction{Float64}, false, true),
            (MOI.ScalarQuadraticFunction{Float64}, true, true),
            (MOI.ScalarNonlinearFunction, false, false),
        ]

        for (function_type, dirac1, dirac3) in objective_rows
            for (device_type, expected) in (("dirac-1", dirac1), ("dirac-3", dirac3))
                optimizer = QCIOpt.Optimizer()
                MOI.set(optimizer, QCIOpt.DeviceType(), device_type)

                @test MOI.supports(
                    optimizer,
                    MOI.ObjectiveFunction{function_type}(),
                ) == expected
            end
        end
    end

    @testset "Unsupported objective reports an MOI error" begin
        model = MOI.Utilities.Model{Float64}()
        x = MOI.add_variable(model)
        MOI.add_constraint(model, x, MOI.ZeroOne())
        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{MOI.VariableIndex}(),
            x,
        )

        optimizer = QCIOpt.Optimizer()
        MOI.set(optimizer, QCIOpt.DeviceType(), "dirac-1")
        MOI.set(
            optimizer,
            MOI.RawOptimizerAttribute("api_token"),
            "offline-token",
        )

        @test_throws MOI.UnsupportedAttribute MOI.optimize!(optimizer, model)
    end

    @testset "Device-specific constraint support" begin
        constraint_rows = [
            (MOI.VariableIndex, MOI.ZeroOne, true, true),
            (MOI.VariableIndex, MOI.Integer, false, true),
            (MOI.VariableIndex, MOI.EqualTo{Float64}, false, true),
            (MOI.VariableIndex, MOI.Interval{Float64}, false, true),
            (MOI.VariableIndex, MOI.GreaterThan{Float64}, false, true),
            (MOI.VariableIndex, MOI.LessThan{Float64}, false, true),
            (
                MOI.ScalarAffineFunction{Float64},
                MOI.EqualTo{Float64},
                false,
                false,
            ),
        ]

        for (function_type, set_type, dirac1, dirac3) in constraint_rows
            for (device_type, expected) in (("dirac-1", dirac1), ("dirac-3", dirac3))
                optimizer = QCIOpt.Optimizer()
                MOI.set(optimizer, QCIOpt.DeviceType(), device_type)

                @test MOI.supports_constraint(optimizer, function_type, set_type) == expected
            end
        end
    end

    @testset "Optimizer attributes" begin
        for device_type in ("dirac-1", "dirac-3")
            optimizer = QCIOpt.Optimizer()
            MOI.set(optimizer, QCIOpt.DeviceType(), device_type)

            supported = [
                QCIOpt.DeviceType(),
                MOI.Silent(),
                MOI.RawOptimizerAttribute("api_token"),
                MOI.RawOptimizerAttribute("device_type"),
                MOI.RawOptimizerAttribute("file_name"),
                MOI.RawOptimizerAttribute("num_samples"),
                MOI.RawOptimizerAttribute("relaxation_schedule"),
                MOI.RawOptimizerAttribute("silent"),
            ]
            unsupported = [
                MOI.TimeLimitSec(),
                MOI.NumberOfThreads(),
                MOI.RawOptimizerAttribute("job_name"),
            ]

            @test all(attr -> MOI.supports(optimizer, attr), supported)
            @test all(attr -> !MOI.supports(optimizer, attr), unsupported)
        end
    end

    @testset "MOI.Silent reaches the QCI client boundary" begin
        python_globals = QCIOpt.PythonCall.pydict()
        QCIOpt.PythonCall.pyexec(
            """
            class OfflineClient:
                last_verbose = None

                def __init__(self, **kwargs):
                    pass

                def upload_file(self, *, file):
                    print("upload output")
                    return {"file_id": "offline-file"}

                def build_job_body(self, **kwargs):
                    print("build output")
                    return {"job_submission": {}}

                def get_allocations(self):
                    print("allocation output")
                    return {"allocations": {"dirac": {"paid": False}}}

                def process_job(self, *, job_body, verbose):
                    type(self).last_verbose = verbose
                    print("process output")
                    return {
                        "status": "COMPLETED",
                        "results": {
                            "solutions": [[0.0, 0.0]],
                            "energies": [0.0],
                            "counts": [1],
                        },
                        "job_info": {},
                    }
            """,
            python_globals,
            python_globals,
        )

        original_client = QCIOpt.qcic.QciClient
        try
            QCIOpt.PythonCall.pysetattr(
                QCIOpt.qcic,
                "QciClient",
                python_globals["OfflineClient"],
            )

            model = MOI.Utilities.Model{Float64}()
            x = MOI.add_variables(model, 2)
            MOI.add_constraint(model, x[1], MOI.ZeroOne())
            MOI.add_constraint(model, x[2], MOI.ZeroOne())
            objective = MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(-2.0, x[1], x[2])],
                [
                    MOI.ScalarAffineTerm(1.0, x[1]),
                    MOI.ScalarAffineTerm(1.0, x[2]),
                ],
                0.0,
            )
            MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
            MOI.set(model, MOI.ObjectiveFunction{typeof(objective)}(), objective)

            offline_client = python_globals["OfflineClient"]
            for device_type in ("dirac-1", "dirac-3")
                for silent in (false, true)
                    optimizer = QCIOpt.Optimizer()
                    MOI.set(optimizer, QCIOpt.DeviceType(), device_type)
                    MOI.set(optimizer, MOI.Silent(), silent)
                    MOI.set(
                        optimizer,
                        MOI.RawOptimizerAttribute("api_token"),
                        "offline-token",
                    )

                    displayed = QCIOpt.Suppressor.@capture_out begin
                        MOI.optimize!(optimizer, model)
                    end

                    @test MOI.get(optimizer, MOI.TerminationStatus()) ==
                          MOI.LOCALLY_SOLVED
                    @test MOI.get(optimizer, MOI.ObjectiveValue(1)) == 0.0
                    @test QCIOpt.PythonCall.pyconvert(
                        Bool,
                        offline_client.last_verbose,
                    ) == !silent

                    visible_output = if device_type == "dirac-3"
                        "allocation output\nupload output\nbuild output\nprocess output\n"
                    else
                        "upload output\nbuild output\nprocess output\n"
                    end
                    normalized_output = replace(displayed, "\r\n" => "\n")
                    @test normalized_output == (silent ? "" : visible_output)
                end
            end
        finally
            QCIOpt.PythonCall.pysetattr(QCIOpt.qcic, "QciClient", original_client)
        end
    end
end
