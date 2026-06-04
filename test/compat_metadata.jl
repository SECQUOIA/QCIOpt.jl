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

    workflow_dir = joinpath(@__DIR__, "..", ".github", "workflows")
    ci = read(joinpath(workflow_dir, "ci.yml"), String)
    docs = read(joinpath(workflow_dir, "docs.yml"), String)
    docscleanup = read(joinpath(workflow_dir, "docscleanup.yml"), String)
    all_workflows = join([ci, docs, docscleanup], "\n")

    function has_ci_matrix_entry(version, os)
        escaped_version = replace(version, "." => "\\.")
        pattern = Regex("- version:\\s*['\"]" * escaped_version * "['\"]\\s*\\n\\s*os:\\s*" * os)
        return occursin(pattern, ci)
    end

    @test has_ci_matrix_entry("1.10", "ubuntu-latest")
    @test has_ci_matrix_entry("1", "ubuntu-latest")
    @test has_ci_matrix_entry("1.10", "windows-latest")
    @test has_ci_matrix_entry("1", "windows-latest")

    @test occursin("uses: actions/checkout@v6", ci)
    @test occursin("uses: julia-actions/setup-julia@v3", ci)
    @test occursin("uses: julia-actions/cache@v3", ci)
    @test occursin("uses: julia-actions/julia-buildpkg@v1", ci)
    @test occursin("uses: julia-actions/julia-runtest@v1", ci)
    @test occursin("uses: actions/checkout@v6", docs)
    @test occursin("uses: julia-actions/setup-julia@v3", docs)
    @test occursin("uses: julia-actions/julia-buildpkg@v1", docs)
    @test occursin("uses: actions/checkout@v6", docscleanup)
    @test !occursin("@latest", all_workflows)
    @test !occursin("actions/checkout@v2", all_workflows)
    @test !occursin("julia-actions/setup-julia@v1", all_workflows)

    dependabot = read(joinpath(@__DIR__, "..", ".github", "dependabot.yml"), String)
    @test occursin(r"package-ecosystem:\s*[\"']?github-actions[\"']?", dependabot)
    @test occursin(r"directory:\s*[\"']?/[\"']?", dependabot)
    @test occursin(r"interval:\s*[\"']?monthly[\"']?", dependabot)
end
