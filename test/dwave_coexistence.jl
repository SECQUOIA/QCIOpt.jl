using Test
using QCIOpt
using DWave

@testset "QCIOpt and DWave CondaPkg coexistence" begin
    @test QCIOpt.Optimizer() isa QCIOpt.Optimizer
    @test DWave.Optimizer() isa DWave.Optimizer
    @test QCIOpt.PythonCall.pyconvert(String, QCIOpt.qcic.__name__) == "qciopt_client"

    networkx_version =
        QCIOpt.PythonCall.pyconvert(String, QCIOpt.PythonCall.pyimport("networkx").__version__)
    @test parse(Int, first(split(networkx_version, '.'))) >= 3
end
