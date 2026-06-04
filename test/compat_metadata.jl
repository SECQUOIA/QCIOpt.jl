using TOML
import Pkg

@testset "compat metadata" begin
    project = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    compat = project["compat"]

    compat_allows_julia_110(compat_table, package) =
        !haskey(compat_table, package) || v"1.10.0" in Pkg.Versions.VersionSpec(compat_table[package])

    @test compat["julia"] == "1.10"
    @test compat_allows_julia_110(compat, "Dates")
    @test compat_allows_julia_110(compat, "LinearAlgebra")
    @test compat_allows_julia_110(Dict("LinearAlgebra" => "1"), "LinearAlgebra")
    @test !compat_allows_julia_110(Dict("LinearAlgebra" => "1.11.0"), "LinearAlgebra")

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
