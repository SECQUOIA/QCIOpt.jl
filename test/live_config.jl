@testset "Live QCI device selection" begin
    @test live_qci_devices(Dict()) == ["dirac-1", "dirac-3"]
    @test live_qci_devices(Dict("QCI_LIVE_DEVICES" => "dirac-3")) == ["dirac-3"]
    @test live_qci_devices(Dict("QCI_LIVE_DEVICES" => "dirac-1")) == ["dirac-1"]
    @test live_qci_devices(Dict("QCI_LIVE_DEVICES" => " dirac-3, dirac-1 ")) ==
          ["dirac-3", "dirac-1"]
    @test live_qci_devices(Dict("QCI_LIVE_DEVICES" => "dirac-3,dirac-3")) == ["dirac-3"]

    # A typo or an empty selection must not turn a live run into a false success.
    for devices in ("", " ", "dirac-2", "dirac-3,", ",dirac-1", "dirac-1,unknown")
        @test_throws ArgumentError live_qci_devices(Dict("QCI_LIVE_DEVICES" => devices))
    end

    withenv("QCI_LIVE_DEVICES" => "dirac-3") do
        @test live_qci_devices() == ["dirac-3"]
    end
end
