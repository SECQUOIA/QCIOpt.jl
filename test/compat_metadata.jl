using TOML
import Pkg

@testset "compat metadata" begin
    project = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    docs_project = TOML.parsefile(joinpath(@__DIR__, "..", "docs", "Project.toml"))
    test_project = TOML.parsefile(joinpath(@__DIR__, "Project.toml"))
    condapkg = TOML.parsefile(joinpath(@__DIR__, "..", "CondaPkg.toml"))
    project_text = read(joinpath(@__DIR__, "..", "Project.toml"), String)
    readme_text = read(joinpath(@__DIR__, "..", "README.md"), String)
    readme_words = replace(readme_text, r"\s+" => " ")
    compat = project["compat"]
    deps = project["deps"]

    compat_allows_julia_110(compat_table, package) =
        !haskey(compat_table, package) || v"1.10.0" in Pkg.Types.semver_spec(compat_table[package])

    version_spec_allows(package, version) =
        Pkg.Versions.VersionNumber(version) in Pkg.Types.semver_spec(compat[package])

    @test compat["julia"] == "1.10"
    @test VersionNumber(project["version"]) isa VersionNumber
    @test compat_allows_julia_110(compat, "Dates")
    @test compat_allows_julia_110(compat, "LinearAlgebra")
    @test compat_allows_julia_110(Dict("LinearAlgebra" => "1"), "LinearAlgebra")
    @test !compat_allows_julia_110(Dict("LinearAlgebra" => "1.11.0"), "LinearAlgebra")

    stdlib_deps = Set(["Dates", "LinearAlgebra"])
    nonstdlib_deps = setdiff(Set(keys(deps)), stdlib_deps)
    @test all(package -> haskey(compat, package), nonstdlib_deps)
    @test all(package -> !startswith(compat[package], "="), nonstdlib_deps)

    @test compat["CondaPkg"] == "0.2.24"
    @test compat["DynamicPolynomials"] == "0.6"
    @test compat["JSON"] == "0.21, 1.6"
    @test compat["MathOptInterface"] == "1.35"
    @test compat["PythonCall"] == "0.9"
    @test compat["Suppressor"] == "0.2"
    @test version_spec_allows("CondaPkg", "0.2.24")
    @test version_spec_allows("CondaPkg", "0.2.36")
    @test !version_spec_allows("CondaPkg", "0.3.0")
    @test version_spec_allows("DynamicPolynomials", "0.6.6")
    @test !version_spec_allows("DynamicPolynomials", "0.7.0")
    @test version_spec_allows("JSON", "0.21.4")
    @test version_spec_allows("JSON", "1.6.1")
    @test !version_spec_allows("JSON", "1.5.2")
    @test version_spec_allows("MathOptInterface", "1.35.0")
    @test version_spec_allows("MathOptInterface", "1.51.1")
    @test !version_spec_allows("MathOptInterface", "1.34.0")
    @test version_spec_allows("PythonCall", "0.9.34")
    @test !version_spec_allows("PythonCall", "0.10.0")
    @test version_spec_allows("Suppressor", "0.2.8")
    @test occursin("Keep CondaPkg on 0.2.x", project_text)
    @test occursin("PythonCall 0.9", project_text)
    @test condapkg["deps"]["python"] == ">=3.8,<=3.12"
    @test condapkg["deps"]["libffi"]["version"] == ">=3.4,<3.5"
    @test condapkg["deps"]["libffi"]["channel"] == "anaconda"
    @test condapkg["pip"]["deps"]["qci-client"] == ">=4.5"
    @test occursin("Pkg.add(url=\"https://github.com/SECQUOIA/QCIOpt.jl\")", readme_text)
    @test occursin("QCIOpt.jl is currently a URL-only package", readme_words)
    @test occursin("not registered in the Julia General registry", readme_words)
    @test occursin("does not use TagBot or registry-based release automation", readme_words)
    @test occursin("source of truth for the package version", readme_words)
    @test occursin("Dependabot and compatibility-only PRs are maintenance changes", readme_words)
    @test occursin("- Bump `version` in `Project.toml`.", readme_text)
    @test occursin("julia --project=. -e 'using Pkg; Pkg.test()'", readme_text)
    @test occursin(
        "julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'",
        readme_text,
    )
    @test occursin("julia --project=docs docs/make.jl", readme_text)
    @test occursin("git tag -a v<version>", readme_text)

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

    function workflow_uses_step(text, uses)
        pattern = Regex(
            "(?ms)^\\s*- uses: " *
            uses *
            "\\s*\\n(.*?)(?=^\\s*- (?:name|uses): |\\z)",
        )
        step = match(pattern, text)
        return isnothing(step) ? "" : step.match
    end

    enables_live_qci_tests(text) =
        occursin(r"(?mi)^\s*QCI_RUN_LIVE_TESTS:\s*['\"]?(?:1|true|yes)['\"]?\s*$", text)

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
    @test !any(file -> occursin("tagbot", lowercase(file)), workflow_files)
    @test !occursin("@latest", all_workflows)
    @test !occursin("TagBot", all_workflows)
    @test !occursin("JuliaRegistrator", all_workflows)
    @test !occursin("JuliaRegistries/RegisterAction", all_workflows)
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
    ci_runtest_step = workflow_uses_step(ci, "julia-actions/julia-runtest@v1")
    @test !occursin(r"(?i)CompatHelper", dependabot)
    @test !any(file -> occursin("compathelper", lowercase(file)), workflow_files)
    @test !occursin(r"(?i)CompatHelper", all_workflows)
    @test !isempty(ci_runtest_step)
    @test !enables_live_qci_tests(ci_runtest_step)
    @test enables_live_qci_tests("env:\n  QCI_RUN_LIVE_TESTS: true\n")
    @test enables_live_qci_tests("env:\n  QCI_RUN_LIVE_TESTS: '1'\n")
    @test !enables_live_qci_tests("env:\n  QCI_RUN_LIVE_TESTS: false\n")

    function dependabot_updates(text)
        updates = String[]
        buffer = IOBuffer()
        in_update = false

        for line in split(text, '\n'; keepempty = true)
            if occursin(r"^\s*-\s+package-ecosystem:", line)
                if in_update
                    push!(updates, String(take!(buffer)))
                end
                in_update = true
            end

            in_update && println(buffer, line)
        end

        in_update && push!(updates, String(take!(buffer)))

        return updates
    end

    function scalar_value(block, key)
        value = match(
            Regex("(?m)^\\s*(?:-\\s*)?" * key * ":\\s*[\"']?([^\"'\\n]+)[\"']?\\s*\$"),
            block,
        )
        return isnothing(value) ? nothing : value.captures[1]
    end

    dependabot_entries = dependabot_updates(dependabot)

    function updates_for(ecosystem, directory)
        return filter(dependabot_entries) do update
            scalar_value(update, "package-ecosystem") == ecosystem &&
                scalar_value(update, "directory") == directory
        end
    end

    function only_update_for(ecosystem, directory)
        updates = updates_for(ecosystem, directory)
        @test length(updates) == 1
        return length(updates) == 1 ? only(updates) : ""
    end

    root_julia = only_update_for("julia", "/")
    @test scalar_value(root_julia, "interval") == "weekly"
    @test occursin("root-julia-dependencies:", root_julia)
    @test occursin(r"(?m)^\s*-\s*[\"']?\*[\"']?\s*$", root_julia)

    @test haskey(docs_project, "compat")
    docs_julia = only_update_for("julia", "/docs")
    @test scalar_value(docs_julia, "interval") == "weekly"
    @test occursin("docs-julia-dependencies:", docs_julia)
    @test occursin(r"(?m)^\s*-\s*[\"']?\*[\"']?\s*$", docs_julia)

    if haskey(test_project, "compat")
        test_julia = only_update_for("julia", "/test")
        @test scalar_value(test_julia, "interval") == "weekly"
    else
        @test isempty(updates_for("julia", "/test"))
    end

    actions = only_update_for("github-actions", "/")
    @test scalar_value(actions, "interval") == "monthly"
end
