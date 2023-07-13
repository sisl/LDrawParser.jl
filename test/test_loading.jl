let
    filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
    model = parse_ldraw_file(filename)
    for (k,p) in model.parts
        @test p.populated.status == false
    end
    @test isempty(model.sub_parts)
    @test !isempty(model.models["20009 - AT-TE Walker.mpd"].steps[1].lines)
    @test length(model.models["20009 - AT-TE Walker.mpd"].steps) == 26
    @test length(model.models["20009 - Light Leg.ldr"].steps) == 4
    @test length(model.models["20009 - Turret.ldr"].steps) == 7

    # load geometry, need ldraw parts library for this to work
    if isdir(get_part_library_dir())
        LDrawParser.populate_part_geometry!(model)
        @test !isempty(model.sub_parts)
        for (k,p) in Base.Iterators.flatten((model.parts,model.sub_parts))
            @assert p.populated.status == true
        end
    else
        @warn "Skipping tests for populate_part_geometry!(...) because $(get_part_library_dir()) does not exist"
    end
end
let
    filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Saturn.mpd")
    model = parse_ldraw_file(filename)
    for (k,p) in model.parts
        @test p.populated.status == false
    end
    @test isempty(model.sub_parts)
    @test !isempty(model.models["21309 - main.ldr"].steps[1].lines)
    @test length(model.models["21309 - main.ldr"].steps) == 57
    @test length(model.models["21309 - 287.ldr"].steps) == 16
    @test length(model.models["21309 - 136-243.ldr"].steps) == 49

    # load geometry, need ldraw parts library for this to work
    if isdir(get_part_library_dir())
        LDrawParser.populate_part_geometry!(model)
        @test !isempty(model.sub_parts)
        for (k,p) in Base.Iterators.flatten((model.parts,model.sub_parts))
            @assert p.populated.status == true
        end
    else
        @warn "Skipping tests for populate_part_geometry!(...) because $(get_part_library_dir()) does not exist"
    end
end
