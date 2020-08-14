using LDrawParser
using Documenter

makedocs(;
    modules=[LDrawParser],
    authors="kylebrown <kylejbrown17@gmail.com> and contributors",
    repo="https://github.com/kylejbrown17/LDrawParser.jl/blob/{commit}{path}#L{line}",
    sitename="LDrawParser.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://kylejbrown17.github.io/LDrawParser.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/kylejbrown17/LDrawParser.jl",
)
