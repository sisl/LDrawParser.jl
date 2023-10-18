using Documenter, LDrawParser

makedocs(
    modules = [LDrawParser],
    format = Documenter.HTML(),
    sitename = "LDrawParser.jl"
)

deploydocs(
    repo = "github.com/sisl/LDrawParser.jl",
    versions = ["stable" => "v^", "v#.#"]
)
