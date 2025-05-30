using Test
using JuMP
using QCIOpt

function main()
    @testset "QCIOpt Tests" begin
        @testset "Problem Format" begin
            # from "https://learn.quantumcomputinginc.com/learn/module/introduction-to-dirac-3/dirac-3-developer-beginner-guide"

            let @polyvar(x[1:2])
                v = [1, 2] # variables
                f = []
                l = [0, 0]
                u = [4, 2]
                p = (1/4) * (x[1]^4 + x[2]^4) - (5/3) * (x[1]^3 + x[2]^3) + 3 * (x[1]^2 + x[2]^2)

                subs, lvls = QCIOpt.get_substitutions_and_levels(

                )
                
                q = QCIOpt.DP.subs(p, r)

                
            end
        end
    end

    return nothing
end

main() # Here we go!
