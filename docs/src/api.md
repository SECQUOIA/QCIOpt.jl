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

## Provider metadata

A solve keeps the QCI job response as the solution metadata verbatim, for both
DIRAC-1 and DIRAC-3. [`QCIOpt.ProviderMetadata`](@ref) reads a normalized view of
it back out:

```julia
using JuMP, QCIOpt

model = Model(QCIOpt.Optimizer)
# ... build and optimize the model ...

metadata = get_attribute(model, QCIOpt.ProviderMetadata())

metadata["job_id"]         # provider job identifier
metadata["run_time_sec"]   # same value as MOI.SolveTimeSec
metadata["error"]          # provider job-error diagnostic, or nothing
metadata["response"]       # the job response itself
```

Every key listed on [`QCIOpt.qci_provider_metadata`](@ref) is always present and
is `nothing` when the response does not carry it, so reading one field never
depends on another being reported. The provider status is also
`MOI.RawStatusString`, and `"run_time_sec"` is `MOI.SolveTimeSec`. Neither fails
on a partial response: a job that did not complete keeps its own provider status
and reports `NaN` for the time, and stored metadata carrying no status string at
all reports `"UNKNOWN"`.

### Relationship to the QUBODrivers sampler metadata

`QCIOpt.DiracSampler` publishes the same provider information under the
standardized [QUBODrivers](https://github.com/JuliaQUBO/QUBODrivers.jl) sampler
keys, which a benchmark harness reads from the `SampleSet`. The two views are
extracted by the same helpers, so they cannot drift:

| `ProviderMetadata` key | `DiracSampler` sample-set metadata          |
|:-----------------------|:--------------------------------------------|
| `"status"`             | `metadata["status"]`                        |
| `"job_id"`             | `metadata["backend"]["job_id"]`             |
| `"result_file_id"`     | `metadata["backend"]["result_file_id"]`     |
| `"problem_file_id"`    | `metadata["backend"]["problem_file_id"]`    |
| `"run_time_sec"`       | (job-status timing; the sampler reports provider metrics under `metadata["time"]`) |
| `"queue_time_sec"`     | (job-status timing; compare `metadata["time"]["provider_queue"]`) |
| `"total_time_sec"`     | (job-status timing; compare `metadata["time"]["provider_wall"]`) |
| `"device_usage_sec"`   | `metadata["time"]["device_usage"]`           |
| `"error"`              | (raw response under `metadata["provider"]`)  |
| `"response"`           | `metadata["provider"]["job_info"]` and siblings |

The sampler additionally queries the provider's job-metrics endpoint, which the
MOI path does not call: its `"time"` entries are nanosecond metrics reported by
that endpoint, while the durations above are derived from the job-status
timestamps that every job response carries. The sampler also records
QUBODrivers' own algorithm, backend, and read-count fields, which describe the
sampler contract rather than the provider.

```@docs
QCIOpt.ProviderMetadata
QCIOpt.qci_provider_metadata
QCIOpt.qci_response_field
QCIOpt.qci_problem_file_id
QCIOpt.qci_provider_error
QCIOpt.qci_get_elapsed_time
QCIOpt.qci_elapsed_seconds
QCIOpt.qci_status_timestamp
QCIOpt.qci_parse_timestamp
QCIOpt.qci_parse_results
QCIOpt.qci_provider_results
```

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
