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
    workflow_files =
        filter(file -> endswith(file, ".yml") || endswith(file, ".yaml"), readdir(workflow_dir))
    workflow_texts = Dict(file => read(joinpath(workflow_dir, file), String) for file in workflow_files)
    ci = workflow_texts["ci.yml"]
    docs = workflow_texts["docs.yml"]
    docscleanup = workflow_texts["docscleanup.yml"]
    all_workflows = join((workflow_texts[file] for file in workflow_files), "\n")

    function has_ci_matrix_entry(version, os)
        escaped_version = replace(version, "." => "\\.")
        pattern = Regex("- version:\\s*['\"]" * escaped_version * "['\"]\\s*\\n\\s*os:\\s*" * os)
        return occursin(pattern, ci)
    end

    function workflow_step(text, name)
        step = match(Regex("(?ms)^\\s*- name: " * name * "\\s*\\n(.*?)(?=^\\s*- name: |\\z)"), text)
        return isnothing(step) ? "" : step.match
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

    docs_build_step = workflow_step(docs, "Build docs")
    docs_deploy_step = workflow_step(docs, "Build and deploy docs")
    docs_cleanup_delete_step = workflow_step(docscleanup, "Delete preview and history")
    docs_cleanup_push_step = workflow_step(docscleanup, "Push changes")
    @test !isempty(docs_build_step)
    @test occursin("if: github.event_name == 'pull_request'", docs_build_step)
    @test occursin(r"(?m)^\s*run:\s*julia --project=docs docs/make\.jl\s*$", docs_build_step)
    @test !occursin("--deploy", docs_build_step)
    @test !occursin("QCI_TOKEN", docs_build_step)
    @test !isempty(docs_deploy_step)
    @test occursin("if: github.event_name != 'pull_request'", docs_deploy_step)
    @test occursin(r"(?m)^\s*run:\s*julia --project=docs docs/make\.jl --deploy\s*$", docs_deploy_step)
    @test occursin("GITHUB_TOKEN", docs_deploy_step)
    @test !occursin("QCI_TOKEN", docs)
    @test !isempty(docs_cleanup_delete_step)
    @test occursin("id: cleanup", docs_cleanup_delete_step)
    @test occursin("if [ ! -d \"previews/PR\$PRNUM\" ]; then", docs_cleanup_delete_step)
    @test occursin("deleted=false", docs_cleanup_delete_step)
    @test occursin("deleted=true", docs_cleanup_delete_step)
    @test !isempty(docs_cleanup_push_step)
    @test occursin("if: steps.cleanup.outputs.deleted == 'true'", docs_cleanup_push_step)

    dependabot = read(joinpath(@__DIR__, "..", ".github", "dependabot.yml"), String)
    @test occursin(r"package-ecosystem:\s*[\"']?github-actions[\"']?", dependabot)
    @test occursin(r"directory:\s*[\"']?/[\"']?", dependabot)
    @test occursin(r"interval:\s*[\"']?monthly[\"']?", dependabot)
end
