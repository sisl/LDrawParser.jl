using LDrawParser
using LightGraphs, GraphUtils
using Logging
using GeometryBasics, CoordinateTransformations, Rotations

# global_logger(SimpleLogger(stderr, Logging.Debug))

filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","ATTEWalker.mpd")
# filename = joinpath(dirname(pathof(LDrawParser)),"..","assets","Millennium Falcon.mpd")
model = parse_ldraw_file(filename)
# load geometry
LDrawParser.populate_part_geometry!(model)


part_keys = sort(collect(keys(model.parts))[1:10])
parts = Dict(k=>model.parts[k] for k in part_keys)
transport_model = (
    robot_radius = 15.0,
    max_area_per_robot = 10000.0, #3000.0,
    max_volume_per_robot = 1000000.0 #20000.0,
)
T = CoordinateTransformations.Translation(0.0,0.0,0.0) ∘ CoordinateTransformations.LinearMap(LDrawParser.LDRAW_BASE_FRAME)
for (k,part) in parts
    points = map(T, LDrawParser.extract_points(part))
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

vis = MeshCat.Visualizer()

POLYHEDRON_MATERIAL = MeshPhongMaterial(color=RGBA{Float32}(1, 0, 0, 0.5))
vis = Visualizer()
render(vis)
vis_root = vis["root"]

SCALE = 0.01
m = model.models["20009 - AT-TE Walker.mpd"]

for step in m.steps
    for ref in step.lines
        global vis_root
        @show ref
        if !LDrawParser.has_part(model,ref.file)
            continue
        end
        p = model.parts[ref.file]
        vec = LDrawParser.extract_surface_geometry(p)
        M = GeometryBasics.Mesh(coordinates(vec)*SCALE,faces(vec))
        setobject!(vis_root[p.name], M)
        tr = LDrawParser.build_transform(ref)
        scaled_tr = compose(CoordinateTransformations.Translation(SCALE*tr.translation),
            CoordinateTransformations.LinearMap(tr.linear)
        )
        settransform!(vis_root[p.name], scaled_tr)
    end
end
p = model.parts["3031.dat"]
vec = LDrawParser.extract_surface_geometry(p)
M = GeometryBasics.Mesh(coordinates(vec)*SCALE,faces(vec))

setobject!(vis["root"][p.name], M)
settransform!(vis[p.name], T)
delete!(vis)


# construct model graph
model_graph = construct_assembly_graph(model)
model_tree = convert(GraphUtils.CustomNTree{GraphUtils._node_type(model_graph),String},model_graph)
@assert maximum(map(v->indegree(model_tree,v),vertices(model_tree))) == 1
print(model_tree,v->summary(v.val),"\t")

sched = LDrawParser.construct_model_schedule(model)
msched = LDrawParser.extract_single_model(sched,"20009 - AT-TE Walker.mpd")

GraphUtils.validate_graph(msched)
