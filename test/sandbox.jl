using LDrawParser
using LightGraphs, GraphUtils

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
# filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
model = parse_ldraw_file(filename)
LDrawParser.populate_part_geometry!(model)
model

"""
    DuplicateIDGenerator{K}

Generates duplicate IDs.
"""
struct DuplicateIDGenerator{K}
    id_counts::Dict{K,Int}
    id_map::Dict{K,K}
    DuplicateIDGenerator{K}() where {K} = new{K}(
        Dict{K,Int}(),
        Dict{K,K}(),
    )
end
_id_type(::DuplicateIDGenerator{K}) = K
function (g::DuplicateIDGenerator)(id)
    k = get!(g.id_map,id,id)
    g.id_counts[k] = get(g.id_counts,k,1) + 1
    new_id = string(k,"-",string(g.id_counts[k]))
    g.id_map[new_id] = id
    new_id
end
function duplicate_subtree!(g,old_root,id_generator,edge_generator=(a,b,c)->1)
    old_node = get_node(g,old_root)
    new_root = add_node!(g,old_node.val,id_generator(get_vtx_id(g,old_root)))
    for v in outneighbors(g,old_root)
        new_v = duplicate_subtree!(g,v,id_generator,edge_generator)
        add_edge!(g,new_root,new_v,edge_generator(g,new_root,new_v))
    end
    return new_root
end

# construct model graph
model_graph = GraphUtils.NEGraph{DiGraph,String,Int,String}()
for (k,m) in model.models
    if !has_vertex(model_graph,k)
        n = add_node!(model_graph,k,k)
    end
    for s in m.steps
        for line in s.lines
            if !has_vertex(model_graph,line.file)
                add_node!(model_graph,line.file,line.file)
            end
            if has_edge(model_graph,n,line.file)
                e = get_edge(model_graph,n,line.file)
                replace_edge!(model_graph,n,line.file,e.val+1)
            else
                add_edge!(model_graph,n,line.file,1)
            end
        end
    end
end
@assert length(get_all_root_nodes(model_graph)) == 1

# convert model graph to a tree nodes wherever necessary to create a tree
g = deepcopy(model_graph)
id_generator=DuplicateIDGenerator{String}()
for v in reverse(topological_sort_by_dfs(g))
    @show v, get_vtx_id(g,v), get_all_root_nodes(g)
    node = get_node(g,v)
    i = 0
    for u in inneighbors(g,v)
        edge = get_edge(g,u,v)
        rem_edge!(g,edge)
        for j in 1:edge.val
            i += 1
            if i > 1
                # duplicate node and add new edge
                n = duplicate_subtree!(g,v,id_generator)
            else
                n = v
            end
            add_edge!(g,GraphUtils.edge_source(edge),n,1)
        end
    end
end
model_tree = convert(GraphUtils.NTree{String,String},g)
@assert length(get_all_root_nodes(model_tree)) == 1
@assert maximum(map(v->indegree(model_tree,v),vertices(model_tree))) == 1
@assert is_connected(model_tree)

print(model_tree,"\t")
# for (partfile,part_model) in model.parts
# end
