using Test
using JuMP
using QCIOpt

import MathOptInterface as MOI

@testset "QCIOpt Tests" begin
    include("test_utils.jl")
    include("compat_metadata.jl")
    include("auth.jl")
    include("offline.jl")
    include("review_regressions.jl")

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
