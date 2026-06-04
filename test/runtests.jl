using Test
using JuMP
using QCIOpt

@testset "QCIOpt Tests" begin
    include("test_utils.jl")
    include("auth.jl")
    include("offline.jl")

    if lowercase(get(ENV, "QCI_RUN_LIVE_TESTS", "false")) in ("1", "true", "yes")
        include("live_qci.jl")
    else
        @info "Skipping live QCI service smoke tests. Set QCI_RUN_LIVE_TESTS=true and QCI_TOKEN to enable them."
    end
end
