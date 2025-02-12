# QCIOpt.jl

[![QUBODRIVERS](https://img.shields.io/badge/Powered%20by-QUBODrivers.jl-%20%234063d8)](https://github.com/JuliaQUBO/QUBODrivers.jl)

Quantum Computing Inc. Optimization Wrapper for JuMP

## Installation
```julia
julia> import Pkg

julia> Pkg.add(url="https://github.com/SECQUOIA/QCIOpt.jl")
```

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

**Disclaimer:** _The QCI Optimization Wrapper for Julia is not officially supported by Quantum Computing Inc. If you are a commercial customer interested in official support for Julia from QCI, let them know!_

**Note**: _If you are using [QCIOpt.jl](https://github.com/SECQUOIA/QCIOpt.jl) in your project, we recommend you to include the `.CondaPkg` entry in your `.gitignore` file. The `PythonCall` module will place a lot of files in this folder when building its Python environment._
