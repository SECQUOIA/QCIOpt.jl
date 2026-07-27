@testset "Documented optimizer attributes" begin
    readme = replace(
        read(joinpath(dirname(@__DIR__), "README.md"), String),
        "\r\n" => "\n",
    )

    has_number_of_reads = occursin("QCIOpt.NumberOfReads()", readme)
    has_api_token_wrapper = occursin("QCIOpt.APIToken()", readme)
    documents_num_samples = occursin(
        "MOI.RawOptimizerAttribute(\"num_samples\")",
        readme,
    )
    documents_api_token = occursin(
        "MOI.RawOptimizerAttribute(\"api_token\")",
        readme,
    )

    @test !has_number_of_reads
    @test !has_api_token_wrapper
    @test documents_num_samples
    @test documents_api_token

    model = Model(QCIOpt.Optimizer)
    num_samples = 17
    api_token = "offline-test-token"

    set_attribute(
        model,
        MOI.RawOptimizerAttribute("num_samples"),
        num_samples,
    )
    set_attribute(
        model,
        MOI.RawOptimizerAttribute("api_token"),
        api_token,
    )

    @test get_attribute(
        model,
        MOI.RawOptimizerAttribute("num_samples"),
    ) == num_samples
    @test get_attribute(
        model,
        MOI.RawOptimizerAttribute("api_token"),
    ) == api_token
end
