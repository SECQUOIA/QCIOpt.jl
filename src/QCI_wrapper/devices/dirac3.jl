@doc raw"""
    DIRAC_3 <: QCI_DIRAC <: QCI_DEVICE

## About

"""
struct DIRAC_3 <: QCI_DIRAC end

QCI_DEVICES["dirac-3"] = DIRAC_3
