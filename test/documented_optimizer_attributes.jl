@testset "Documented optimizer attributes" begin
    readme = replace(
        read(joinpath(dirname(@__DIR__), "README.md"), String),
        "\r\n" => "\n",
    )

    has_number_of_reads = occursin("QCIOpt.NumberOfReads()", readme)
    has_api_token_wrapper = occursin("QCIOpt.APIToken()", readme)
    has_direct_moi_import = occursin(
        "import MathOptInterface as MOI",
        readme,
    )
    documents_num_samples = occursin(
        "set_attribute(model, \"num_samples\", 10)",
        readme,
    )
    documents_api_token = occursin(
        "set_attribute(model, \"api_token\", ENV[\"QCI_TOKEN\"])",
        readme,
    )

    @test !has_number_of_reads
    @test !has_api_token_wrapper
    @test !has_direct_moi_import
    @test documents_num_samples
    @test documents_api_token

    model = Model(QCIOpt.Optimizer)
    num_samples = 17
    api_token = "offline-test-token"

    set_attribute(model, "num_samples", num_samples)
    set_attribute(model, "api_token", api_token)

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
        set_attribute(model, "num_samples", 17)
        set_attribute(model, "api_token", "offline-test-token")

        @assert get_attribute(model, "num_samples") == 17
        @assert get_attribute(model, "api_token") == "offline-test-token"
        """
        command = `$(Base.julia_cmd()) --startup-file=no --project=$project_dir -e $script`
        separator = Sys.iswindows() ? ';' : ':'
        load_path = string(project_dir, separator, "@stdlib")

        @test success(addenv(command, "JULIA_LOAD_PATH" => load_path))
    end
end
