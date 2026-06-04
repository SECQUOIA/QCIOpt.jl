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
