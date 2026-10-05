function live_qci_devices(env = ENV)
    devices = unique(strip.(split(get(env, "QCI_LIVE_DEVICES", "dirac-1,dirac-3"), ',')))
    all(device -> device in ("dirac-1", "dirac-3"), devices) ||
        throw(ArgumentError("QCI_LIVE_DEVICES must list dirac-1 and/or dirac-3, separated by commas"))
    return devices
end

function with_qci_token(f::Function, value)
    had_token = haskey(ENV, "QCI_TOKEN")
    old_env = get(ENV, "QCI_TOKEN", "")
    old_ref = QCIOpt.QCI_TOKEN[]

    try
        if isnothing(value)
            delete!(ENV, "QCI_TOKEN")
        else
            ENV["QCI_TOKEN"] = value
        end

        QCIOpt.QCI_TOKEN[] = "stale-token"

        return f()
    finally
        if had_token
            ENV["QCI_TOKEN"] = old_env
        else
            delete!(ENV, "QCI_TOKEN")
        end

        QCIOpt.QCI_TOKEN[] = old_ref
    end
end
