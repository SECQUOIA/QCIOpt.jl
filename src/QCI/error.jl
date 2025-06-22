abstract type QCI_ERROR <: Exception end

struct QCI_UNSUPPORTED_DEVICE_ERROR <: QCI_ERROR
    spec::String
end

function Base.showerror(io::IO, e::QCI_UNSUPPORTED_DEVICE_ERROR)
    specs = join(map(s -> "'$s'", qci_supported_devices()), ", ", " and ")

    println(io, "Unsupported device specification: '$(e.spec)'. Options are: $(specs).")
end

struct QCI_HTTP_ERROR <: QCI_ERROR
    code::Int
    msg::String
end

function Base.showerror(io::IO, qci_err::QCI_HTTP_ERROR)
    println(io, "HTTP Error $(qci_err.code): QCI: $(qci_err.msg)")
end

struct QCI_UNAUTHORIZED_API_TOKEN_ERROR <: QCI_ERROR end

function Base.showerror(io::IO, ::QCI_UNAUTHORIZED_API_TOKEN_ERROR)
    println(io, "QCI: Unauthorized API Token")
end

function qci_specialize_http_error(qcierr::QCI_HTTP_ERROR)
    if qcierr.code == 401 && qcierr.msg == "Unauthorized"
        return QCI_UNAUTHORIZED_API_TOKEN_ERROR()
    else
        return qcierr # No particular specialization found
    end
end

function qci_parse_error(err)
    if err isa PythonCall.PyException
        PythonCall.pyisinstance(err, requests.exceptions.HTTPError) || return nothing
        PythonCall.pyhasattr(err, "args")                           || return nothing

        let args = PythonCall.pygetattr(err, "args")
            PythonCall.pylen(args) == 1 || return nothing

            let msg = only(args)
                PythonCall.pyisinstance(msg, PythonCall.pytype(PythonCall.pystr(""))) || return nothing
                
                let m = match(
                        r"([0-9]+) Client Error: Unauthorized for url: (.*) with response body: (.*)",
                        PythonCall.pyconvert(String, msg),
                    )
                    isnothing(m) && return nothing

                    code     = parse(Int, m[1])
                    response = JSON.parse(m[3])

                    qcierr = QCI_HTTP_ERROR(code, String(response["message"]))

                    return qci_specialize_http_error(qcierr)
                end
            end
        end
    end

    return nothing
end


