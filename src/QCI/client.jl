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

    output = Ref{String}("")

    return try
        local result # https://github.com/JuliaIO/Suppressor.jl?tab=readme-ov-file#variable-scope

        output[] = @capture_out begin
            result = callback(client)
        end

        silent || print(output[])

        return (;
            result = result,
            output = output,
            error  = nothing,
        )
    catch err
        qcierr = qci_parse_error(err)

        silent || print(output[])

        isnothing(qcierr) && rethrow(err)

        return (;
            result = nothing,
            output = output,
            error  = qcierr,
        )
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
