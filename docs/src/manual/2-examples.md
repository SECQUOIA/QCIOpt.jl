# Examples

```@example
using QCIOpt
using JuMP

model = Model(QCIOpt.Optimizer)

@variable(model, -10 <= x[1:5] <= 4, Int)

@objective(model, Min, sum((-1)^(i + j) * x[i] * x[j] for i = 1:3 for j = 1:3))

model
```
