using Documenter
using QCIOpt

# Set up to run docstrings with jldoctest
DocMeta.setdocmeta!(QCIOpt, :DocTestSetup, :(using QCIOpt); recursive = true)

makedocs(;
    modules  = [QCIOpt],
    doctest  = true,
    clean    = true,
    warnonly = [:missing_docs, :cross_references],
    format   = Documenter.HTML( #
        sidebar_sitename = false,
        mathengine       = Documenter.KaTeX(),
        assets           = [ #
            "assets/extra_styles.css",
            "assets/favicon.ico",
        ]
    ),
    sitename = "QCIOpt.jl",
    authors  = "Pedro Maciel Xavier and Yirang Park",
    pages    = [ # 
        "Home"          => "index.md",
        "Manual"        => [ #
            "Introduction" => "manual/1-introduction.md",
            "Examples"     => "manual/2-examples.md",
        ],
        "API Reference" => "api.md",
    ],
    workdir = @__DIR__,
)

if "--deploy" ∈ ARGS
    deploydocs(repo = raw"github.com/SECQUOIA/QCIOpt.jl.git", push_preview = true)
else
    @warn "Skipping deployment"
end
