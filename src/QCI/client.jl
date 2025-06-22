struct BufferPipe <: Base.AbstractPipe
    io::IOBuffer
    silent::Bool

    BufferPipe(; silent::Bool = false) = new(IOBuffer(), silent)
end

Base.pipe_writer(bp::BufferPipe) = bp.io

@doc raw"""
    qci_client_wrapper
"""
function qci_client_wrapper end

function qci_client_wrapper(
        callback::Function,
        client::Any;
        silent::Bool = false,
    )

    pipeio = BufferPipe()

    return try
        result = redirect_stdout(() -> callback(client), pipeio)

        closewrite(pipeio)

        output = read(pipeio, String)

        silent || print(output)

        return (;
            result = result,
            output = output,
            error  = nothing,
        )
    catch err
        qcierr = qci_parse_error(err)
        
        closewrite(pipeio)

        output = read(pipeio, String)

        silent || print(output)

        isnothing(qcierr) && rethrow(err)

        return (;
            result = nothing,
            output = nothing,
            error  = qcierr,
        )
    end
end

@doc raw"""
    qci_auth_client
"""
function qci_auth_client end

function qci_auth_client(;
        url::AbstractString              = QCI_URL,
        api_token::Maybe{AbstractString} = QCI_TOKEN[],
    )
    @assert !isnothing(api_token) "API Token was not provided."

    return qcic.auth.client.AuthClient(; url, api_token)
end

function qci_auth_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = QCI_TOKEN[],
    silent::Bool                             = false,
)
    client = qci_auth_client(; url, api_token)

    return qci_client_wrapper(callback, client; silent)
end

@doc raw"""
    qci_client()

## Example

```julia
QCIOpt.qci_client(QCIOpt.qci_device("dirac-3")) do (client, device)
    @show device
    @show client.get_allocations()
end
```
"""
function qci_client end

function qci_client(;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = QCI_TOKEN[],
)
    @assert !isnothing(api_token) "API Token was not provided."

    return qcic.QciClient(; url, api_token)
end

function qci_client(
    callback::Function;
    url::AbstractString                      = QCI_URL,
    api_token::Union{AbstractString,Nothing} = QCI_TOKEN[],
    silent::Bool                             = false,
)
    client = qci_client(; url, api_token)
    
    return qci_client_wrapper(callback, client; silent)
end

function qci_get_allocations(; url::AbstractString = QCI_URL, api_token::Maybe{AbstractString} = QCI_TOKEN[], silent::Bool = false)
    alloc = QCIOpt.qci_client(; url, api_token, silent) do client
        return client.get_allocations() |> jl_object
    end

    return alloc["allocations"]
end
