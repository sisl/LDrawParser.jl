using LDrawParser

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
# filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
model = parse_ldraw_file(filename)
LDrawParser.populate_part_geometry!(model)

# for (partfile,part_model) in model.parts
# end
