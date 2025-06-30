function test_interface()
    @testset "▶ Interface" begin
        @testset "Authentication" begin
            @test QCIOpt.__auth__()
            
            QCIOpt.qci_is_free_tier() && @info "Running Tests in QCI Free Tier"
        end

        let alloc = QCIOpt.qci_get_allocations()
            @test haskey(alloc, "dirac")
        end

        @test QCIOpt.qci_device_type(Float32, "dirac-1") === QCIOpt.DIRAC_1{Float32}
        @test QCIOpt.qci_device_type(Float32, "dirac-3") === QCIOpt.DIRAC_3{Float32}

        @test QCIOpt.qci_device(Float64, "dirac-1") isa QCIOpt.DIRAC_1{Float64}
        @test QCIOpt.qci_device(Float64, "dirac-3") isa QCIOpt.DIRAC_3{Float64}
    end

    return nothing
end
