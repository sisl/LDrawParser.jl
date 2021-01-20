let
    filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
    # filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
    model = parse_ldraw_file(filename)
    for (k,p) in model.parts
        @test p.populated.status == false
    end
    @test isempty(model.sub_parts)
    @test !isempty(model.models["20009 - AT-TE Walker.mpd"].steps[1].lines)
    # load geometry
    if isdir(get_part_library_dir())
        LDrawParser.populate_part_geometry!(model)
        for (k,p) in Base.Iterators.flatten((model.parts,model.sub_parts))
            @assert p.populated.status == true
        end
    else
        @warn "Skipping tests for populate_part_geometry!(...) because $(get_part_library_dir()) does not exist"
    end

end
