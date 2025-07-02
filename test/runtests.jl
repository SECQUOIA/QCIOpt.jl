using Test
using JuMP
using QCIOpt

include("interface.jl")
include("examples.jl")

function main()
    @testset "QCIOpt Tests" begin
        test_interface()   
        test_examples()     
    end

    return nothing
end

main() # Here we go!
