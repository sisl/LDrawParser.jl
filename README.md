# LDrawParser

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://kylejbrown17.github.io/LDrawParser.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://kylejbrown17.github.io/LDrawParser.jl/dev)
[![Build Status](https://github.com/kylejbrown17/LDrawParser.jl/workflows/CI/badge.svg)](https://github.com/kylejbrown17/LDrawParser.jl/actions)

A package for parsing [LDraw]{https://www.ldraw.org/} files for LEGO CAD applications.

Example usage:

```Julia
path = "/path/to/ldraw_file.mpd" # or .ldr
model = parse_ldraw_file(path)
model.models
model.parts
```
