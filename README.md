# LDrawParser
[![CI](https://github.com/sisl/LDrawParser.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/sisl/LDrawParser.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/JuliaPOMDP/SARSOP.jl/branch/master/graph/badge.svg?token=c4tQjlMbDX)](https://codecov.io/gh/SISL/LDrawParser.jl)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://SISL.github.io/LDrawParser.jl/stable)

A package for parsing [LDraw](https://www.ldraw.org/) files for LEGO CAD applications.

Example usage:

```Julia
path = "/path/to/ldraw_file.mpd" # or .ldr
model = parse_ldraw_file(path)
model.models
model.parts
```
