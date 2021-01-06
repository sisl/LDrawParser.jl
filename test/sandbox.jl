using LDrawParser
using LightGraphs, GraphUtils

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
# filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
model = parse_ldraw_file(filename)
LDrawParser.populate_part_geometry!(model)
model

# construct model graph
model_graph = construct_assembly_graph(model)
# vtxs = collect(get_all_root_nodes(model_graph))
# nodes = map(v->get_node(model_graph,v),vtxs)
# id_generator=DuplicateIDGenerator{String}()
# model_graph = GraphUtils.NEGraph{DiGraph,String,Int,String}()
# for (k,m) in model.models
#     # if !has_vertex(model_graph,k)
#         n = add_node!(model_graph,k,k)
#     # end
#     for s in m.steps
#         for line in s.lines
#             # if !has_vertex(model_graph,line.file)
#             #     np = add_node!(model_graph,line.file,line.file)
#             # else
#             #     np = add_node!(model_graph,line.file,id_generator(line.file))
#             # end
#             # if has_edge(model_graph,n,line.file)
#             # if has_edge(model_graph,n,np)
#             #     e = get_edge(model_graph,n,line.file)
#             #     replace_edge!(model_graph,n,line.file,e.val+1)
#             # else
#             #     add_edge!(model_graph,n,line.file,1)
#             # end
#             np = add_node!(model_graph,line.file,id_generator(line.file))
#             add_edge!(model_graph,n,np,1)
#         end
#     end
# end
# for (k,m) in model.models
#     node = get_node(model_graph,k)
#     for v in outneighbors(model_graph,k)
#         child = get_node(model_graph,v)
#         if haskey(model.models,GraphUtils.node_val(child)) # is_submodel
#             sub_model_id = GraphUtils.node_val(child)
#             np = duplicate_subtree!(model_graph,sub_model_id,id_generator)
#             add_edge!(model_graph,node,np,1)
#         end
#     end
# end
# @assert length(get_all_root_nodes(model_graph)) == 1

# convert model graph to a tree nodes wherever necessary to create a tree
# g = deepcopy(model_graph)
# id_generator=DuplicateIDGenerator{String}()
# for v in reverse(topological_sort_by_dfs(g))
#     @show v, get_vtx_id(g,v), get_all_root_nodes(g)
#     node = get_node(g,v)
#     i = 0
#     for u in inneighbors(g,v)
#         edge = get_edge(g,u,v)
#         rem_edge!(g,edge)
#         for j in 1:edge.val
#             i += 1
#             if i > 1
#                 # duplicate node and add new edge
#                 n = duplicate_subtree!(g,v,id_generator)
#             else
#                 n = v
#             end
#             add_edge!(g,GraphUtils.edge_source(edge),n,1)
#         end
#     end
# end
model_tree = convert(GraphUtils.CustomNTree,model_graph)
# @assert length(get_all_root_nodes(model_tree)) == 1
@assert maximum(map(v->indegree(model_tree,v),vertices(model_tree))) == 1
# @assert is_connected(model_tree)

print(model_tree,GraphUtils.node_id,"\t")
# for (partfile,part_model) in model.parts
# end
