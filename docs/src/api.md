# API Reference

## Devices

```@docs
QCIOpt.QCI_DEVICE
QCIOpt.DeviceType
QCIOpt.qci_device
QCIOpt.qci_device_type
QCIOpt.qci_supports_device
QCIOpt.qci_supported_devices
```

## MathOptInterface capabilities

Capabilities follow the selected [`QCIOpt.DeviceType`](@ref). Changing the
device updates `MOI.supports` and `MOI.supports_constraint` immediately.

| MOI surface | DIRAC-1 | DIRAC-3 |
|:------------|:-------:|:-------:|
| Scalar-quadratic objective | yes | yes |
| `VariableIndex` or scalar-affine objective | no | yes |
| Scalar-nonlinear objective | no | no |
| `VariableIndex` in `ZeroOne` | yes | yes |
| `VariableIndex` in `Integer` | no | yes |
| `VariableIndex` in `EqualTo`, `Interval`, `GreaterThan`, or `LessThan` | no | yes |
| Scalar or vector functional constraints | no | no |
| `MIN_SENSE` / `MAX_SENSE` | yes | yes |
| `FEASIBILITY_SENSE` | no | no |

DIRAC-1 accepts binary unconstrained quadratic models. DIRAC-3's bound
constraint declarations describe finite integer domains: each non-fixed
variable must also be `Integer` or `ZeroOne`; `EqualTo` and a zero-width
`Interval` represent a fixed single level. General continuous boxes and
functional constraints are not supported.

Both devices support `MOI.ObjectiveSense` for `MIN_SENSE` and `MAX_SENSE`,
[`QCIOpt.DeviceType`](@ref), `MOI.Silent`, and the raw optimizer attributes
`"api_token"`, `"device_type"`, `"file_name"`, `"num_samples"`, `"job_name"`,
`"job_tags"`, and `"silent"`. DIRAC-3 additionally supports
`"relaxation_schedule"`. Job parameters use the same names, ranges, and defaults
documented in the README; DIRAC-3 derives `num_levels` from the model rather
than exposing it as a raw attribute. The devices do not support
`MOI.TimeLimitSec`, `MOI.NumberOfThreads`, or arbitrary raw attributes.
`MOI.Silent = true` suppresses console output from file upload, job-body
construction, and job processing while leaving solver results and provider
metadata unchanged.

## DIRAC-3 variable transformation

DIRAC-3 samples each variable over consecutive integer levels starting at zero.
[`QCIOpt.variable_domains`](@ref) states the full contract that maps a bounded
integer JuMP/MOI model onto those levels and back; the remaining functions
implement its individual steps.

```@docs
QCIOpt.variable_domains
QCIOpt.qci_build_poly_request
QCIOpt.rescale_variables
QCIOpt.get_levels
QCIOpt.assert_level_budget
QCIOpt.readjust_poly_values
```

## QCI service helpers

```@docs
QCIOpt.qci_build_job_body
QCIOpt.qci_build_poly_job_body
QCIOpt.qci_is_free_tier
QCIOpt.qci_max_level
QCIOpt.qci_process_job
```
