using LDrawParser

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
model = parse_ldraw_file(filename)
# PART_LIBRARY_DIR = joinpath(ENV["HOME"],".cache/LeoCAD Software/LeoCAD/")
PART_LIBRARY_DIR = "/scratch/ldraw_parts_library/ldraw/parts/"


# for (partfile,part_model) in model.parts
partfile = collect(keys(model.parts))[1]
    state = LDrawParser.MPDModelState(active_part=partfile)
    if splitext(partfile)[end] == ".dat"
        parse_ldraw_file!(model,joinpath(PART_LIBRARY_DIR,partfile),state)
    end
# end
