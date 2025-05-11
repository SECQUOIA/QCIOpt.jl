# Examples

```@example
using QCIOpt
using JuMP

model = Model(QCIOpt.Optimizer)

@variable(model, 0 <= x[1:5] <= 10, Int)

@objective(model, Min, sum(i * (-1)^i * x[i] for i = 1:5))

model
```
