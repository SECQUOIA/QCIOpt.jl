using TOML

@testset "compat metadata" begin
    project = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    compat = project["compat"]

    @test compat["julia"] == "1.10"
    @test !haskey(compat, "Dates")
    @test !haskey(compat, "LinearAlgebra")

    ci = read(joinpath(@__DIR__, "..", ".github", "workflows", "ci.yml"), String)

    function has_ci_matrix_entry(version, os)
        escaped_version = replace(version, "." => "\\.")
        pattern = Regex("- version:\\s*['\"]" * escaped_version * "['\"]\\s*\\n\\s*os:\\s*" * os)
        return occursin(pattern, ci)
    end

    @test has_ci_matrix_entry("1.10", "ubuntu-latest")
    @test has_ci_matrix_entry("1", "ubuntu-latest")
    @test has_ci_matrix_entry("1.10", "windows-latest")
    @test has_ci_matrix_entry("1", "windows-latest")
end
