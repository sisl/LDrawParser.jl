using LDrawParser
using LightGraphs, GraphUtils

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
# filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
model = parse_ldraw_file(filename)
LDrawParser.populate_part_geometry!(model)
model

# k = "44728.dat"
k = "43710.dat"
geometry = LDrawParser.extract_geometry(model.parts[k])
points = LDrawParser.extract_points(model.parts[k])

part_keys = sort(collect(keys(model.parts))[1:10])
parts = Dict(k=>model.parts[k] for k in part_keys)

transport_model = (
    robot_radius = 15.0,
    max_area_per_robot = 10000.0, #3000.0,
    max_volume_per_robot = 1000000.0 #20000.0,
)
for (k,part) in parts
    points = LDrawParser.extract_points(part)
    if isempty(points)
        println("Part $k has no geometry!")
        continue
    end
    geom=map(SVector,points)
    try
        support_pts = HierarchicalGeometry.select_support_locations(
            geom,transport_model)
        polygon = VPolygon(convex_hull(map(p->p[1:2],geom)))

        plt = plot(polygon,aspectratio=1,alpha=0.4)
        scatter!(plt,map(p->p[1],geom),map(p->p[2],geom),label=k) #,legend=false)
        plot!(plt,map(p->Ball2(p,transport_model.robot_radius),support_pts), aspectratio=1, alpha=0.4)
        display(plt)
    catch e
        bt = catch_backtrace()
        showerror(stdout,e,bt)
    end
end

# construct model graph
model_graph = construct_assembly_graph(model)
model_tree = convert(GraphUtils.CustomNTree{GraphUtils._node_type(model_graph),String},model_graph)
@assert maximum(map(v->indegree(model_tree,v),vertices(model_tree))) == 1
print(model_tree,v->summary(v.val),"\t")

sched = LDrawParser.construct_model_schedule(model)
msched = LDrawParser.extract_single_model(sched,"20009 - AT-TE Walker.mpd")

GraphUtils.validate_graph(msched)
