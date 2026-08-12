# QCIOpt.jl

[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/JuliaQUBO/QUBODrivers.jl)

Quantum Computing Inc. Optimization Wrapper for JuMP

## Installation
```julia
julia> import Pkg

julia> Pkg.add(url="https://github.com/SECQUOIA/QCIOpt.jl", rev="v0.2.0")
```

## QCIOpt and DWave

QCIOpt and DWave can be installed in the same Julia environment with the
default CondaPkg backend. QCIOpt does not install the `qci-client` distribution,
whose `networkx<3` requirement conflicts with D-Wave Ocean. Instead, QCIOpt
ships the small Qatalyst REST-client subset it uses and keeps its managed Python
requirements to `numpy` and `requests`.

No `JULIA_CONDAPKG_BACKEND=Null` or separately managed Python environment is
needed for this supported configuration. CI imports QCIOpt and DWave v0.7.6
together with NetworkX 3 to guard the reproducible shared-environment contract.
A nonblocking scheduled canary also tracks DWave's default branch so upstream
dependency changes are visible without weakening the pinned regression.

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

## Changing the backend device

Device selection uses a typed first-party optimizer attribute, while the
provider-specific tunables and credentials below use JuMP's raw optimizer
attribute names. Selecting a device loads its default attributes, so choose the
device before setting any tunables or credentials.

```julia
set_attribute(model, QCIOpt.DeviceType(), "dirac-1")
```

## Updating optimization parameters

QCIOpt exposes provider-specific settings through JuMP's raw optimizer
attribute names. Supported job parameters depend on the selected device:

| Attribute | Type | Default | Devices | Provider field |
|:----------|:-----|:--------|:--------|:---------------|
| `"num_samples"` | integer in `1:100` | `10` | DIRAC-1, DIRAC-3 | device configuration |
| `"relaxation_schedule"` | integer in `1:4` | `1` | DIRAC-3 | device configuration |
| `"job_name"` | string | `""` | DIRAC-1, DIRAC-3 | job submission |
| `"job_tags"` | vector of strings | `String[]` | DIRAC-1, DIRAC-3 | job submission |

DIRAC-3 additionally derives its per-variable `num_levels` vector from the
validated integer domains; it is not a user-settable raw attribute. Unsupported
raw attributes and invalid values fail at the MOI boundary instead of being
silently dropped.

```julia
set_attribute(model, "num_samples", 10)
```

## API Token

To access QCI's devices, create an account at
[QCI](https://quantumcomputinginc.com/learn/developer-resources/entropy-quantum-optimization/qci-client-quick-start)
and provide the API token through the `QCI_TOKEN` environment variable or an
approved secret store. Do not commit or print the token.

```shell
$ export QCI_TOKEN="<your-qci-token>"
```

The `"api_token"` raw optimizer attribute accepts the token as a string. QCIOpt
also reads `QCI_TOKEN` when the package loads. To configure a model explicitly,
read the same environment variable rather than embedding the token in source:

```julia
set_attribute(model, "api_token", ENV["QCI_TOKEN"])
```

Treat the token and optimizer state as sensitive. Reading the `"api_token"`
attribute or dumping optimizer attributes can expose the credential; do not
print either while debugging.

Live QCI smoke tests are optional. Set both `QCI_TOKEN` and
`QCI_RUN_LIVE_TESTS=true` in the environment; for example:

```shell
$ QCI_RUN_LIVE_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'
```

In GitHub Actions, live QCI tests run from the manual and weekly scheduled
`Live QCI` workflow. The default CI workflow runs offline tests only.

**Disclaimer:** _The QCI Optimization Wrapper for Julia is not officially supported by Quantum Computing Inc. If you are a commercial customer interested in official support for Julia from QCI, let them know!_

**Note**: _If you are using [QCIOpt.jl](https://github.com/SECQUOIA/QCIOpt.jl) in your project, we recommend you to include the `.CondaPkg` entry in your `.gitignore` file. The `PythonCall` module will place a lot of files in this folder when building its Python environment._
