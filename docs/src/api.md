# API Reference

## Devices

```@docs
QCIOpt.QCI_DEVICE
QCIOpt.qci_device
QCIOpt.qci_device_type
QCIOpt.qci_supports_device
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
