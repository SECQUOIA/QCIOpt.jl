@testset "Documented optimizer attributes" begin
    readme = replace(
        read(joinpath(dirname(@__DIR__), "README.md"), String),
        "\r\n" => "\n",
    )

    has_number_of_reads = occursin("QCIOpt.NumberOfReads()", readme)
    has_api_token_wrapper = occursin("QCIOpt.APIToken()", readme)
    has_moi_reference = occursin(
        "MathOptInterface",
        readme,
    )
    device_example_position = findfirst(
        "set_attribute(model, QCIOpt.DeviceType(), \"dirac-1\")",
        readme,
    )
    documents_num_samples = occursin(
        "set_attribute(model, \"num_samples\", 10)",
        readme,
    )
    num_samples_example_position = findfirst(
        "set_attribute(model, \"num_samples\", 10)",
        readme,
    )
    documents_api_token = occursin(
        "set_attribute(model, \"api_token\", ENV[\"QCI_TOKEN\"])",
        readme,
    )
    api_token_example_position = findfirst(
        "set_attribute(model, \"api_token\", ENV[\"QCI_TOKEN\"])",
        readme,
    )
    documents_safe_configuration_order =
        device_example_position !== nothing &&
        num_samples_example_position !== nothing &&
        api_token_example_position !== nothing &&
        first(device_example_position) < first(num_samples_example_position) <
        first(api_token_example_position)
    explains_attribute_idioms = occursin(
        "typed first-party optimizer attribute",
        readme,
    )
    explains_device_reset = occursin(
        "Selecting a device loads its default attributes",
        readme,
    )
    documents_token_export = occursin(
        "export QCI_TOKEN=\"<your-qci-token>\"",
        readme,
    )
    warns_token_readback =
        occursin("Reading the `\"api_token\"`", readme) &&
        occursin("dumping optimizer attributes", readme) &&
        occursin("expose the credential", readme)
    documents_live_test_opt_in =
        occursin("Live QCI smoke tests are optional", readme) &&
        occursin("Set both `QCI_TOKEN`", readme) &&
        occursin("`QCI_RUN_LIVE_TESTS=true`", readme)

    @test !has_number_of_reads
    @test !has_api_token_wrapper
    @test !has_moi_reference
    @test documents_num_samples
    @test documents_api_token
    @test documents_safe_configuration_order
    @test explains_attribute_idioms
    @test explains_device_reset
    @test documents_token_export
    @test warns_token_readback
    @test documents_live_test_opt_in

    model = Model(QCIOpt.Optimizer)
    num_samples = 17
    api_token = "offline-test-token"

    set_attribute(model, QCIOpt.DeviceType(), "dirac-1")
    set_attribute(model, "num_samples", num_samples)
    set_attribute(model, "api_token", api_token)

    @test get_attribute(model, QCIOpt.DeviceType()) == "dirac-1"
    @test get_attribute(model, "num_samples") == num_samples
    @test get_attribute(model, "api_token") == api_token

    mktempdir() do project_dir
        write(
            joinpath(project_dir, "Project.toml"),
            """
            [deps]
            JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
            QCIOpt = "6e1d72ef-e149-4f5c-9c69-bc0273b92dbc"
            """,
        )
        # Reuse the test manifest to keep this dependency-surface check offline
        # and fast; fresh resolution is verified separately before release.
        cp(
            joinpath(dirname(Base.active_project()), "Manifest.toml"),
            joinpath(project_dir, "Manifest.toml"),
        )

        script = """
        import Pkg
        using JuMP
        using QCIOpt

        @assert !haskey(Pkg.project().dependencies, "MathOptInterface")

        model = Model(QCIOpt.Optimizer)
        set_attribute(model, QCIOpt.DeviceType(), "dirac-1")
        set_attribute(model, "num_samples", 17)
        ENV["QCI_TOKEN"] = "offline-test-token"
        set_attribute(model, "api_token", ENV["QCI_TOKEN"])

        @assert get_attribute(model, QCIOpt.DeviceType()) == "dirac-1"
        @assert get_attribute(model, "num_samples") == 17
        @assert get_attribute(model, "api_token") == "offline-test-token"
        """
        command = `$(Base.julia_cmd()) --startup-file=no --project=$project_dir -e $script`
        separator = Sys.iswindows() ? ';' : ':'
        load_path = string(project_dir, separator, "@stdlib")

        @test success(addenv(command, "JULIA_LOAD_PATH" => load_path))
    end
end
