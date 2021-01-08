let
    filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
    # filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
    model = parse_ldraw_file(filename)
    for (k,p) in model.parts
        @test p.populated.status == false
    end
    @test isempty(model.sub_parts)
    # load geometry
    LDrawParser.populate_part_geometry!(model)
    for (k,p) in Base.Iterators.flatten((model.parts,model.sub_parts))
        @assert p.populated.status == true
    end

end
