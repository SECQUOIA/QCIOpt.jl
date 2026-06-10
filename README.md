# QCIOpt.jl

[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/JuliaQUBO/QUBODrivers.jl)

Quantum Computing Inc. Optimization Wrapper for JuMP

## Installation
```julia
julia> import Pkg

julia> Pkg.add(url="https://github.com/SECQUOIA/QCIOpt.jl")
```

## Release Workflow

QCIOpt.jl is currently a URL-only package. It is not registered in the Julia
General registry, and this repository does not use TagBot or registry-based
release automation. Install from the repository URL until the project explicitly
chooses registry distribution.

`Project.toml` is the source of truth for the package version. Dependabot and
compatibility-only PRs are maintenance changes; they are not release-significant
unless a maintainer intentionally includes a version bump and release work.

Manual release checklist:

- Bump `version` in `Project.toml`.
- Run package tests with `julia --project=. -e 'using Pkg; Pkg.test()'`.
- Prepare the docs environment with
  `julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'`.
- Build docs without deployment with `julia --project=docs docs/make.jl`.
- Create an annotated tag matching the package version, for example
  `git tag -a v<version> -m "QCIOpt v<version>"`.
- Push the release commit and tag after review.

## Basic Usage
```julia
using JuMP
using QCIOpt

model = Model(QCIOpt.Optimizer)

Q = [
   -1  2  2
    2 -1  2
    2  2 -1
]

@variable(model, x[1:3], Bin)
@objective(model, Min, x' * Q * x)

optimize!(model)

for i = 1:result_count(model)
    xi = value.(x; result=i)
    yi = objective_value(model; result=i)

    println("f($xi) = $yi")
end
```

## Updating optimization parameters

```julia
set_attribute(model, QCIOpt.NumberOfReads(), 10) # Number of samples
```

## Changing the backend device

```julia
set_attribute(model, QCIOpt.DeviceType(), "dirac-1")
```

## API Token
To access QCI's devices, it is necessary to create an account at [QCI](https://quantumcomputinginc.com/learn/developer-resources/entropy-quantum-optimization/qci-client-quick-start) to obtain an API Token and define 

```julia
set_attribute(model, QCIOpt.APIToken(), "your_token_here")
```

Another option is to set the `QCI_TOKEN` environment variable before loading `QCIOpt.jl`:

```shell
$ export QCI_TOKEN="your_token_here"

$ julia

julia> using QCIOpt
```

Live QCI smoke tests are optional and require credentials. To run them locally, set
`QCI_RUN_LIVE_TESTS=true` and `QCI_TOKEN`, then execute:

```shell
$ QCI_RUN_LIVE_TESTS=true QCI_TOKEN="your_token_here" julia --project=. -e 'using Pkg; Pkg.test()'
```

In GitHub Actions, live QCI tests run only from the manual `Live QCI`
workflow. The default CI workflow runs offline tests only.

**Disclaimer:** _The QCI Optimization Wrapper for Julia is not officially supported by Quantum Computing Inc. If you are a commercial customer interested in official support for Julia from QCI, let them know!_

**Note**: _If you are using [QCIOpt.jl](https://github.com/SECQUOIA/QCIOpt.jl) in your project, we recommend you to include the `.CondaPkg` entry in your `.gitignore` file. The `PythonCall` module will place a lot of files in this folder when building its Python environment._
