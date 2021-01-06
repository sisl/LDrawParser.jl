using LDrawParser
using LightGraphs, GraphUtils

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
# filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
model = parse_ldraw_file(filename)
LDrawParser.populate_part_geometry!(model)
model

# construct model graph
model_graph = construct_assembly_graph(model)
model_tree = convert(GraphUtils.CustomNTree{GraphUtils._node_type(model_graph),String},model_graph)
# @assert length(get_all_root_nodes(model_tree)) == 1
@assert maximum(map(v->indegree(model_tree,v),vertices(model_tree))) == 1
# @assert is_connected(model_tree)

print(model_tree,v->summary(v.val),"\t")
# for (partfile,part_model) in model.parts
# end
node = get_node(model_tree,"20009 - Turret.ldr-2")

sched = LDrawParser.construct_model_schedule(model)

LDrawParser.extract_single_model(sched,"20009 - AT-TE Walker.mpd")
