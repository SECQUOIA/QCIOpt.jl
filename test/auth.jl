@testset "Authentication" begin
    for token in (nothing, "", " \t\n")
        with_qci_token(token) do
            @test !QCIOpt.__auth__()
            @test QCIOpt.QCI_TOKEN[] === nothing
        end
    end

    with_qci_token("test-token") do
        @test QCIOpt.__auth__()
        @test QCIOpt.QCI_TOKEN[] == "test-token"
    end

    code = "using QCIOpt; exit(QCIOpt.QCI_TOKEN[] === nothing ? 0 : 1)"
    test_project = dirname(Base.active_project())
    cmd = `$(Base.julia_cmd()) --project=$test_project -e $code`

    @test success(addenv(cmd, "QCI_TOKEN" => ""))
end
