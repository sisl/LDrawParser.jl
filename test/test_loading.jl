
orig_part_dir = LDrawParser.get_part_library_dir()

# set the temporary parts library for testing
LDrawParser.set_part_library_dir!(joinpath(dirname(pathof(LDrawParser)), "..", "assets", "test_parts_lib"))

let
    filename = joinpath(dirname(pathof(LDrawParser)), "..", "assets", "20009-1 - AT-TE Walker - Mini.mpd")
    model = parse_ldraw_file(filename; ignore_rotation_determinant=true)
    for (k, p) in model.parts
        @test p.populated.status == false
    end
    @test isempty(model.sub_parts)
    @test !isempty(model.models["20009 - AT-TE Walker.mpd"].steps[1].lines)
    @test length(model.models["20009 - AT-TE Walker.mpd"].steps) == 9
    @test length(model.models["20009 - Light Leg.ldr"].steps) == 4
    @test length(model.models["20009 - Turret.ldr"].steps) == 7


    LDrawParser.populate_part_geometry!(model; ignore_rotation_determinant=true)
    @test !isempty(model.sub_parts)
    for (k, p) in Base.Iterators.flatten((model.parts, model.sub_parts))
        @assert p.populated.status == true
    end
end
let
    filename = joinpath(dirname(pathof(LDrawParser)), "..", "assets", "21309-1 - NASA Apollo Saturn V.mpd")
    model = parse_ldraw_file(filename; ignore_rotation_determinant=true)
    for (k, p) in model.parts
        @test p.populated.status == false
    end
    @test isempty(model.sub_parts)
    @test !isempty(model.models["21309 - main.ldr"].steps[1].lines)
    @test length(model.models["21309 - main.ldr"].steps) == 26
    @test length(model.models["21309 - 287.ldr"].steps) == 8
    @test length(model.models["21309 - 136-243.ldr"].steps) == 14

    # load geometry, need ldraw parts library for this to work
    LDrawParser.populate_part_geometry!(model; ignore_rotation_determinant=true)
    @test !isempty(model.sub_parts)
    for (k, p) in Base.Iterators.flatten((model.parts, model.sub_parts))
        @assert p.populated.status == true
    end
end
let
    filename = joinpath(dirname(pathof(LDrawParser)), "..", "assets", "6339-1 - Shuttle Launch Pad.mpd")
    model = parse_ldraw_file(filename; ignore_rotation_determinant=true)
    LDrawParser.populate_part_geometry!(model; ignore_rotation_determinant=false)
    ldraw_color_dict = LDrawParser.get_color_dict()
    LDrawParser.change_coordinate_system!(model, ldraw_base_transform(), 0.1; ignore_rotation_determinant=true)
    get_part(model, 0)
    get_part(model, "3938.dat")
end

# reset the parts library
LDrawParser.set_part_library_dir!(orig_part_dir)
