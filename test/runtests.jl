using Test
using JuMP
using QCIOpt

import MathOptInterface as MOI

@testset "QCIOpt Tests" begin
    include("test_utils.jl")
    include("compat_metadata.jl")
    include("auth.jl")
    include("client_bridge.jl")
    include("job_parameters.jl")
    include("documented_optimizer_attributes.jl")
    include("offline.jl")
    include("qubodrivers_sampler.jl")
    include("review_regressions.jl")
    include("moi_result_semantics.jl")
    include("provider_metadata.jl")
    include("dirac3_bounds.jl")
    include("moi_capabilities.jl")

    if lowercase(get(ENV, "QCI_RUN_LIVE_TESTS", "false")) in ("1", "true", "yes")
        include("live_qci.jl")
        include("interface.jl")
        include("examples.jl")

        test_interface()
        test_examples()
    else
        @info "Skipping live QCI service tests. Set QCI_RUN_LIVE_TESTS=true and QCI_TOKEN to enable them."
    end
end
