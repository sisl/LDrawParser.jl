# LDrawParser
[![CI](https://github.com/sisl/LDrawParser.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/sisl/LDrawParser.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/JuliaPOMDP/SARSOP.jl/branch/master/graph/badge.svg?token=c4tQjlMbDX)](https://codecov.io/gh/SISL/LDrawParser.jl)
[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://SISL.github.io/LDrawParser.jl/stable)

A package for parsing [LDraw™](https://www.ldraw.org/) files. As stated on the LDraw website, LDraw is an open standard for LEGO CAD programs that enables the creation of virtual LEGO models. This package allows you to parse LDraw™ files into a Julia data structure. 

### Example usage:

```Julia
using LDrawParser
path = "/path/to/ldraw_file.mpd" # or .ldr
model = parse_ldraw_file(path)
model.models
model.parts
```

## Installation

### Module
To install the module, run the following command in the Julia REPL:
```Julia
] add https://github.com/sisl/LDrawParser.jl.git
```

### Parts Library
It is recommended to download the LDraw parts library to get full use out of your models. Functionality still exists without the parts library, including parsing the build steps, but individual part geometry is recommended for most applications. The parts library can be downloaded from [LDraw™ Parts Library](https://library.ldraw.org/updates?latest). Place the unzipped library in your desired path. The default path assumed by LDrawParser is `joinpath(homedir(), "Documents/ldraw")`. It is recommended to download the complete library (~80 MB zipped, ~450 MB unzipped).

If you did not place the parts library in the default path, you can change the path LDrawParser uses by the `set_part_library_dir!` command. For example, if you placed the parts library in the assets directory, you can run the following command in the Julia REPL:
```Julia
using LDrawParser
set_part_library_dir!("assets/ldraw")
```

## Usage

A handful of models are provided in the assets directory. In this example, we are reading in the tractor model and populating the part geometry. We then use the `change_coordinate_system!` function to change the coordinate system from the LDraw system to the standard right-handed system and scale the model by 0.5.

```Julia
filename = joinpath(dirname(dirname(pathof(LDrawParser))), "assets", "tractor.mpd")
model = parse_ldraw_file(filename)

# Populate the part geometry
populate_part_geometry!(model)

# Change the coordiante system from the LDraw system to the standard right-handed system and scale model by 0.5
LDrawParser.change_coordinate_system!(model, ldraw_base_transform(), 0.5)
```