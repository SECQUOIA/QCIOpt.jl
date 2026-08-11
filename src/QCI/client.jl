@doc raw"""
    qci_client_wrapper(callback, client; silent = false)

Run `callback(client)` and return a named tuple containing the callback result,
captured output, and any parsed QCI error. Parsed provider errors are returned in
the `error` field; other exceptions are rethrown.
"""
function qci_client_wrapper end

function qci_client_wrapper(
        callback::Function,
        client::Any;
        silent::Bool = false,
    )

    capturing = ccall(:jl_generating_output, Cint, ()) == 0
    capture_open = capturing
    output = Ref{String}("")

    if capturing
        original_stdout = stdout
        out_rd, out_wr = redirect_stdout()
        out_reader = @async read(out_rd, String)
    end

    finish_capture! = function ()
        if capture_open
            redirect_stdout(original_stdout)
            close(out_wr)
            capture_open = false
            return fetch(out_reader)
        end
        return ""
    end

    return try
        result = try
            callback(client)
        finally
            # Python buffers stdout when Julia redirects the file descriptor.
            # Flush before the capture ends so output cannot leak after a
            # silent provider call returns.
            PythonCall.pyimport("sys").stdout.flush()
        end

        output[] = finish_capture!()
        silent || print(output[])

        return (;
            result = result,
            output = output,
            error  = nothing,
        )
    catch err
        output[] = finish_capture!()
        qcierr = qci_parse_error(err)

        silent || print(output[])

        isnothing(qcierr) && rethrow(err)

        return (;
            result = nothing,
            output = output,
            error  = qcierr,
        )
    finally
        finish_capture!()
    end
end

@doc raw"""
    qci_auth_client(; url = QCI_URL, api_token = qci_default_token())
    qci_auth_client(callback; url = QCI_URL, api_token = qci_default_token(), silent = false)

Create a QCI authentication client, or run `callback` with one. The callback
form returns the callback result after applying QCI error parsing.
"""
function qci_auth_client end

function qci_auth_client(;
        url::AbstractString              = QCI_URL,
        api_token::Maybe{AbstractString} = qci_default_token(),
    )
    @assert !isnothing(api_token) "API Token was not provided."

    return qcic.auth.client.AuthClient(; url, api_token)
end

function qci_capture_auth_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = qci_default_token(),
    silent::Bool                             = false,
)
    client = qci_auth_client(; url, api_token)

    return qci_client_wrapper(callback, client; silent)
end

function qci_auth_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = qci_default_token(),
    silent::Bool                             = false,
)
    response = qci_capture_auth_client(callback; url, api_token, silent)

    return response.result
end

@doc raw"""
    qci_client(; url = QCI_URL, api_token = qci_default_token())
    qci_client(callback; url = QCI_URL, api_token = qci_default_token(), silent = false)

Create a QCI optimization client, or run `callback` with one. The callback form
returns the callback result after applying QCI error parsing.

## Example

```julia
QCIOpt.qci_client() do client
    client.get_allocations()
end
```
"""
function qci_client end

function qci_client(;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = qci_default_token(),
)
    @assert !isnothing(api_token) "API Token was not provided."

    return qcic.QciClient(; url, api_token)
end

function qci_capture_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = qci_default_token(),
    silent::Bool                             = false,
)
    client = qci_client(; url, api_token)

    return qci_client_wrapper(callback, client; silent)
end

function qci_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = qci_default_token(),
    silent::Bool                             = false,
)
    response = qci_capture_client(callback; url, api_token, silent)

    return response.result
end

@doc raw"""
    qci_get_allocations(; url = QCI_URL, api_token = qci_default_token(), silent = false)

Return the `"allocations"` object reported by the QCI API for the configured
token.
"""
function qci_get_allocations(;
    url::AbstractString = QCI_URL,
    api_token::Maybe{AbstractString} = qci_default_token(),
    silent::Bool = false,
)
    alloc = QCIOpt.qci_client(; url, api_token, silent) do client
        return client.get_allocations() |> jl_object
    end

    return alloc["allocations"]
end
