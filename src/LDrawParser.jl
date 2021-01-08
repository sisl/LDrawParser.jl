module LDrawParser

using LightGraphs
using GraphUtils
using GeometryBasics
using Rotations, CoordinateTransformations
using Parameters
using Logging

export
    get_part_library_dir,
    set_part_library_dir!,
    find_part_file

global PART_LIBRARY_DIR = "/scratch/ldraw_parts_library/ldraw/"
get_part_library_dir() = deepcopy(PART_LIBRARY_DIR)
function set_part_library_dir!(path)
    PART_LIBRARY_DIR = path
end

function find_part_file(name,library=get_part_library_dir())
    if isfile(name)
        return name
    end
    for (root,dirs,_) in walkdir(library)
        for dir in dirs
            d = joinpath(root,dir)
            for p in [joinpath(d,name),joinpath(d,lowercase(name))]
                if isfile(p)
                    return p
                end
            end
        end
    end
    println("Part file ",name," not found in library at ",library)
end

@enum FILE_TYPE begin
    MODEL
    PART
    SUBPART
    PRIMITIVE
    SHORTCUT
    NONE_FILE_TYPE
end

# Each line of an LDraw file begins with a number 0-5
@enum COMMAND_CODE begin
    META          = 0
    SUB_FILE_REF  = 1
    LINE          = 2
    TRIANGLE      = 3
    QUADRILATERAL = 4
    OPTIONAL      = 5
end

@enum META_COMMAND begin
    FILE
    STEP
    FILE_TYPE_DECLARATION
    OTHER_META_COMMAND
end

const FILE_TYPE_DICT = Dict{String,FILE_TYPE}(
    "MODEL"                     => MODEL,
    "PART"                      => PART,
    "UNOFFICIAL_PART"           => PART,
    "SUBPART"                   => SUBPART,
    "UNOFFICIAL_SUBPART"        => SUBPART,
    "PRIMITIVE"                 => PRIMITIVE,
    "8_PRIMITIVE"               => PRIMITIVE,
    "48_PRIMITIVE"              => PRIMITIVE,
    "UNOFFICIAL_PRIMITIVE"      => PRIMITIVE,
    "UNOFFICIAL_8_PRIMITIVE"    => PRIMITIVE,
    "UNOFFICIAL_48_PRIMITIVE"   => PRIMITIVE,
    "UNOFFICIAL_SHORTCUT"       => PRIMITIVE,
    "SHORTCUT"                  => SHORTCUT,
)
const FILE_TYPE_HEADERS = Set{String}([
    "!LDRAW_ORG",
    "LDRAW_ORG",
    "OFFICIAL LCAD",
    "OFFICIAL",
    "UNOFFICIAL",
    "UN-OFFICIAL"
])
const META_COMMAND_DICT = Dict{String,META_COMMAND}(
    "FILE"          =>FILE,
    "STEP"          =>STEP,
    [k=>FILE_TYPE_DECLARATION for k in FILE_TYPE_HEADERS]...
)

function parse_line(line)
    if Base.Sys.isunix()
        line = replace(line,"\\"=>"/") # switch from Windows directory delimiters to Unix
    end
    split_line = split(line)
    return split_line
end
const SplitLine = Vector{A} where {A<:AbstractString}

parse_file_type(k::AbstractString)      = get(FILE_TYPE_DICT,uppercase(k), NONE_FILE_TYPE)
parse_command_code(k::AbstractString)   = COMMAND_CODE(parse(Int,k))
parse_meta_command(k::AbstractString)   = get(META_COMMAND_DICT,uppercase(k), OTHER_META_COMMAND)
for op in [:parse_file_type, :parse_command_code, :parse_meta_command]
    @eval $op(split_line::SplitLine) = $op(split_line[1])
end

const Point3D   = Point{3,Float64}

"""
    NgonElement

Represents geometry from an LDraw file
"""
struct NgonElement{E}
    color::Int
    geom::E
end

"""
    OptionalLineElement

Represents optional line geometry from an LDraw file
"""
struct OptionalLineElement
    color::Int
    geom::Line
    control_pts::Line
end

"""
    SubFileRef

Represents a sub-file reference from an LDraw file. Encodes the placement of a
part or submodel.
"""
struct SubFileRef
    color::Int
    pos::Point3D
    rot::Mat{3,3,Float64}
    file::String
end
Base.summary(s::SubFileRef) = string("SubFileRef → ",s.file," : ",s.pos)
model_name(r::SubFileRef) = r.file

"""
    BuildingStep

Represents a sequence of part placements that make up a building step in a LDraw
file.
"""
struct BuildingStep
    lines::Vector{SubFileRef}
    BuildingStep() = new(Vector{SubFileRef}())
end
Base.push!(step::BuildingStep,ref::SubFileRef) = push!(step.lines,ref)
n_lines(s::BuildingStep) = length(s.lines)
# Base.string(s::BuildingStep) = string("BuildingStep:",map(r->string("\n  ",string(r)), s.lines)...)
# Base.show(io::IO,s::BuildingStep) = print(io,string(s))

"""
    SubModelPlan

Represents the sequence of building steps that make up a sub model in an LDraw
file
"""
struct SubModelPlan
    name::String
    steps::Vector{BuildingStep}
    SubModelPlan(name::String) = new(
        name,
        Vector{BuildingStep}([BuildingStep()])
        )
end
model_name(r::SubModelPlan) = r.name
n_build_steps(m::SubModelPlan) = length(m.steps)
n_components(m::SubModelPlan) = sum(map(n_lines,m.steps))
Base.summary(n::SubModelPlan) = string("SubModelPlan: ",model_name(n),": ",
    n_build_steps(n)," building steps, ",n_components(n)," components")

export
    MPDModel,
    parse_ldraw_file!,
    parse_ldraw_file


const Quadrilateral{Dim,T} = GeometryBasics.Ngon{Dim,T,4,Point{Dim,T}}
mutable struct Toggle
    status::Bool
end

"""
    DATModel

Encodes the raw geometry of a LDraw part stored in a .dat file. It is possible
to avoid populating the geometry fields, which is useful for large models or
models that use parts from the LDraw library.
"""
struct DATModel
    name::String
    line_geometry::Vector{NgonElement{Line{3,Float64}}}
    triangle_geometry::Vector{NgonElement{Triangle{3,Float64}}}
    quadrilateral_geometry::Vector{NgonElement{Quadrilateral{3,Float64}}}
    optional_line_geometry::Vector{OptionalLineElement}
    subfiles::Vector{SubFileRef} # points to other DATModels
    populated::Toggle
    DATModel(name::String) = new(
        name,
        Vector{NgonElement{Line{3,Float64}}}(),
        Vector{NgonElement{Triangle{3,Float64}}}(),
        Vector{NgonElement{Quadrilateral{3,Float64}}}(),
        Vector{OptionalLineElement}(),
        Vector{String}(),
        Toggle(false)
    )
end
model_name(r::DATModel) = r.name
function extract_geometry(m::DATModel)
    elements = Vector{GeometryBasics.Ngon}()
    for vec in (
            m.line_geometry,
            m.triangle_geometry,
            m.quadrilateral_geometry,
            m.optional_line_geometry
        )
        for e in vec
            push!(elements,e.geom)
        end
    end
    elements
end
function extract_points(m::DATModel)
    pts = Vector{Point3{Float64}}()
    for e in extract_geometry(m)
        for pt in e.points
            push!(pts,pt)
        end
    end
    pts
end

"""
    MPDModel

The MPD model stores the information contained in a .mpd or .ldr file. This
includes a submodel tree (stored implicitly in a dictionary that maps model_name
to SubModelPlan) and a part list. The first model in MPDModel.models is the main
model. All the following are submodels of that model and/or each other.
"""
struct MPDModel
    models::Dict{String,SubModelPlan} # each file is a list of steps
    parts::Dict{String,DATModel}
    # steps
    MPDModel() = new(
        Dict{String,SubModelPlan}(),
        Dict{String,DATModel}()
    )
end

struct LDRGeometry
    lines::Vector{NgonElement{Line{3,Float64}}}
    triangles::Vector{NgonElement{Triangle{3,Float64}}}
    quadrilaterals::Vector{NgonElement{Quadrilateral{3,Float64}}}
    optional_lines::Vector{OptionalLineElement}
    populated::Toggle
    LDRGeometry() = new(
        Vector{NgonElement{Line{3,Float64}}}(),
        Vector{NgonElement{Triangle{3,Float64}}}(),
        Vector{NgonElement{Quadrilateral{3,Float64}}}(),
        Vector{OptionalLineElement}(),
        Toggle(false)
    )
end

struct LDRModel
    name::String
    file_type::FILE_TYPE
    geometry::LDRGeometry
    building_steps::Vector{BuildingStep}
    sub_file_refs::Vector{SubFileRef}
end

@with_kw_noshow mutable struct MPDModelState
    file_type::FILE_TYPE = NONE_FILE_TYPE
    active_model::String = ""
    active_part::String = ""
end

Base.summary(s::MPDModelState) = string(
"MPDModelState(file_type=$(s.file_type), active_model=$(s.active_model), active_part=$(s.active_part))")

update_state(state::MPDModelState) = MPDModelState(state) # TODO deal with single step macro commands, etc.
function active_building_step(submodel::SubModelPlan,state)
    @assert !isempty(submodel.steps)
    active_step = submodel.steps[end]
end
function active_submodel(model::MPDModel,state)
    @assert !isempty(model.models)
    return model.models[state.active_model]
end
function set_new_active_model!(model::MPDModel,state,name)
    @assert !haskey(model.models,name)
    model.models[name] = SubModelPlan(name)
    return MPDModelState(state,active_model=name)
end
function active_building_step(model::MPDModel,state)
    active_model = active_submodel(model,state)
    return active_building_step(active_model,state)
end
function set_new_active_building_step!(model::SubModelPlan)
    push!(model.steps,BuildingStep())
    return model
end
function set_new_active_building_step!(model::MPDModel,state)
    active_model = active_submodel(model,state)
    set_new_active_building_step!(active_model)
    return model
end
function active_part(model::MPDModel,state)
    @assert !isempty(model.parts)
    return model.parts[state.active_part]
end
function set_new_active_part!(model::MPDModel,state,name)
    @assert !haskey(model.parts,name) "$name is already in model.parts!"
    model.parts[name] = DATModel(name)
    println("Active part = $name")
    return MPDModelState(state,active_part=name)
end
function add_sub_file_placement!(model::MPDModel,state,ref)
    # TODO figure out how to place a subfile that is not part of a build step,
    # but is rather (presumably) a subfile of a .dat model
    if state.file_type == MODEL
        if state.active_model != ""
            push!(active_building_step(model,state),ref)
        end
    else
        if state.active_part != ""
            # @info "pushing subfile reference to $(state.active_part)"
            push!(active_part(model,state).subfiles,ref)
        end
    end
    if !haskey(model.parts,ref.file)
        model.parts[ref.file] = DATModel(ref.file)
    end
    return state
end

"""
    parse_ldraw_file!

Args:
    - model
    - filename or IO
"""
function parse_ldraw_file!(model,io,state = MPDModelState())
    # state = MPDModelState()
    for line in eachline(io)
        try
            # if length(state.active_part) > 0
            #     @show line
            #     @show summary(state)
            # end
            if length(line) == 0
                continue
            end
            split_line = parse_line(line)
            if isempty(split_line[1])
                continue
            end
            code = parse_command_code(split_line)
            if code == META
                state = read_meta_line!(model,state,split_line)
            elseif code == SUB_FILE_REF
                state = read_sub_file_ref!(model,state,split_line)
            # Geometry
            elseif code == LINE
                state = read_line!(model,state,split_line)
            elseif code == TRIANGLE
                state = read_triangle!(model,state,split_line)
            elseif code == QUADRILATERAL
                state = read_quadrilateral!(model,state,split_line)
            elseif code == OPTIONAL
                state = read_optional_line!(model,state,split_line)
            end
        catch e
            @show state
            rethrow(e)
        end
    end
    return model
end
function parse_ldraw_file!(model,filename::String,args...)
    open(filename,"r") do io
        parse_ldraw_file!(model,io,args...)
    end
end
parse_ldraw_file(io) = parse_ldraw_file!(MPDModel(),io)
parse_color(c) = parse(Int,c)


"""
    read_meta_line(model,state,line)

Modifies the model and parser_state based on a META command. For example, the
FILE meta command indicates the beginning of a new file, so this creates a new
active model into which subsequent building steps will be placed.
The STEP meta command indicates the end of the current step, which prompts the
parser to close the current build step and begin a new one.
"""
function read_meta_line!(model,state,line)
    @assert parse_command_code(line[1]) == META
    if length(line) < 2
        @info "Returning because length(line) < 2. Usually this means the end of the file"
        return state
    end
    # cmd = line[2]
    cmd = parse_meta_command(line[2])
    if cmd == FILE
        filename = join(line[3:end]," ")
        ext = splitext(filename)[2]
        if ext == ".dat"
            state = set_new_active_part!(model,state,filename)
        elseif ext == ".mpd" || ext == ".ldr"
            state = set_new_active_model!(model,state,filename)
        end
        @info "file = $filename"
    elseif cmd == STEP
        set_new_active_building_step!(model,state)
    elseif cmd == FILE_TYPE_DECLARATION
        state.file_type = parse_file_type(line[3])
        if state.file_type == NONE_FILE_TYPE
            @debug "file type not resolved on line : $line"
        end
        @info "file_type=$state.file_type"
    else
        # TODO Handle other META commands, especially BFC
    end
    return state
end

"""
    read_sub_file_ref

Receives a SUB_FILE_REF line (with the leading SUB_FILE_REF id stripped)
"""
function read_sub_file_ref!(model,state,line)
    @assert parse_command_code(line[1]) == SUB_FILE_REF
    @assert length(line) >= 15 "$line"
    color = parse_color(line[2])
    # coordinate of part
    x,y,z = parse.(Float64,line[3:5])
    # rotation of part
    rot_mat = collect(transpose(reshape(parse.(Float64,line[6:14]),3,3)))
    file = join(line[15:end]," ")
    # TODO add a line struct to the model
    ref = SubFileRef(
        color,
        Point3D(x,y,z),
        Mat{3,3,Float64}(rot_mat),
        file
    )
    add_sub_file_placement!(model,state,ref)
    # push!(model.sub_file_refs,ref)
    return state
end

"""
    read_line!

For reading lines of type LINE
"""
function read_line!(model,state,line)
    @assert parse_command_code(line[1]) == LINE
    @assert length(line) == 8 "$line"
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64,line[3:5]))
    p2 = Point3D(parse.(Float64,line[6:8]))
    # add to model
    push!(
        active_part(model,state).line_geometry,
        NgonElement(color,Line(p1,p2))
        )
    return state
end

"""
    read_triangle!

For reading lines of type TRIANGLE
"""
function read_triangle!(model,state,line)
    @assert parse_command_code(line[1]) == TRIANGLE
    @assert length(line) == 11 "$line"
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64,line[3:5]))
    p2 = Point3D(parse.(Float64,line[6:8]))
    p3 = Point3D(parse.(Float64,line[9:11]))
    # add to model
    push!(
        active_part(model,state).triangle_geometry,
        NgonElement(color,Triangle(p1,p2,p3))
        )
    return state
end

"""
    read_quadrilateral!

For reading lines of type QUADRILATERAL
"""
function read_quadrilateral!(model,state,line)
    @assert parse_command_code(line[1]) == QUADRILATERAL
    @assert length(line) == 14 "$line"
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64,line[3:5]))
    p2 = Point3D(parse.(Float64,line[6:8]))
    p3 = Point3D(parse.(Float64,line[9:11]))
    p4 = Point3D(parse.(Float64,line[12:14]))
    # add to model
    push!(
        active_part(model,state).quadrilateral_geometry,
        NgonElement(color,GeometryBasics.Quadrilateral(p1,p2,p3,p4))
        )
    return state
end

"""
    read_optional_line!

For reading lines of type OPTIONAL
"""
function read_optional_line!(model,state,line)
    @assert parse_command_code(line[1]) == OPTIONAL
    @assert length(line) == 14
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64,line[3:5]))
    p2 = Point3D(parse.(Float64,line[6:8]))
    p3 = Point3D(parse.(Float64,line[9:11]))
    p4 = Point3D(parse.(Float64,line[12:14]))
    # add to model
    push!(
        active_part(model,state).optional_line_geometry,
        OptionalLineElement(
            color,
            Line(p1,p2),
            Line(p3,p4)
        ))
    return state
end


export populate_part_geometry!

"""
    populate_part_geometry!(model,part_keys=Set(collect(keys(model.parts))))

Populate `model` with geometry (from ".dat" files only) of all parts that belong
to model and whose names are included in `part_keys`.
"""
function populate_part_geometry!(model,part_keys=Set(collect(keys(model.parts))))
    excluded_keys = setdiff(Set(collect(keys(model.parts))), part_keys)
    explored = Set{String}()
    while !isempty(part_keys)
        while !isempty(part_keys)
            partfile = pop!(part_keys)
            populate_part_geometry!(model,partfile)
            push!(explored,partfile)
        end
        part_keys = setdiff(Set(collect(keys(model.parts))),union(explored,excluded_keys))
    end
    return model
end
function populate_part_geometry!(model,partfile::String)
    state = LDrawParser.MPDModelState(active_part=partfile)
    if splitext(partfile)[end] == ".dat"
        println("PART FILE ",partfile)
        part = model.parts[partfile]
        if part.populated.status
            println("Geometry already populated for part ",partfile)
            return false
        else
            parse_ldraw_file!(model,find_part_file(partfile),state)
            part.populated.status = true
            return true
        end
    end
end

function (t::AffineMap)(g::G) where {G<:GeometryBasics.Ngon}
    G(map(t,g.points))
end
(t::AffineMap)(g::G) where {G<:NgonElement} = G(g.color,t(g.geom))
(t::AffineMap)(g::G) where {G<:OptionalLineElement} = G(g.color,t(g.geom),t(g.control_pts))
function Base.:(*)(r::Rotation,g::G) where {G<:GeometryBasics.Ngon}
    G(map(p->r*p,g.points))
end

################################################################################
############################ Constructing Model Tree ###########################
################################################################################

# model::MPDModel - model.parts contains raw geometry of all parts
# assembly_tree::AssemblyTree - stored transforms of all parts and submodels
# model_schedule - encodes the partial ordering of assembly operations.

export
    DuplicateIDGenerator,
    duplicate_subtree!,
    construct_assembly_graph

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
_id_type(::DuplicateIDGenerator{K}) where {K} = K
function (g::DuplicateIDGenerator)(id)
    k = get!(g.id_map,id,id)
    g.id_counts[k] = get(g.id_counts,k,0) + 1
    new_id = string(k,"-",string(g.id_counts[k]))
    g.id_map[new_id] = id
    new_id
end
function duplicate_subtree!(g,old_root,d=:out)
    old_node = get_node(g,old_root)
    new_root = add_node!(g,old_node.val)
    if d == :out
        for v in outneighbors(g,old_root)
            new_v = duplicate_subtree!(g,v,d)
            add_edge!(g,new_root,new_v)
        end
    elseif d == :in
        for v in inneighbors(g,old_root)
            new_v = duplicate_subtree!(g,v,d)
            add_edge!(g,new_v,new_root)
        end
    else
        throw(ErrorException("direction must be :in or :out, can't be $d"))
    end
    return new_root
end
# duplicate_subtree!(g::MPDModelGraph,v) = duplicate_subtree!(g,v,g.id_generator)

"""
    MPDModelGraph{N,ID} <: AbstractCustomNDiGraph{CustomNode{N,ID},ID}

Graph to represent the modeling operations required to build a LDraw model.
Currently used both as an assembly tree and a "model schedule".
In the model schedule, the final model is the root of the graph, and its
ancestors are the operations building up thereto.
"""
@with_kw_noshow struct MPDModelGraph{N,ID} <: AbstractCustomNDiGraph{CustomNode{N,ID},ID}
    graph       ::DiGraph                   = DiGraph()
    nodes       ::Vector{CustomNode{N,ID}}  = Vector{CustomNode{N,ID}}()
    vtx_map     ::Dict{ID,Int}              = Dict{ID,Int}()
    vtx_ids     ::Vector{ID}                = Vector{ID}() # maps vertex uid to actual graph node
    id_generator::DuplicateIDGenerator{ID}  = DuplicateIDGenerator{ID}()
end
create_node_id(g,v::BuildingStep) = g.id_generator("BuildingStep")
create_node_id(g,v::SubModelPlan) = has_vertex(g,model_name(v)) ? g.id_generator(model_name(v)) : model_name(v)
create_node_id(g,v::SubFileRef)   = g.id_generator(model_name(v))
function GraphUtils.add_node!(g::MPDModelGraph{N,ID},val::N) where {N,ID}
    id = create_node_id(g,val)
    add_node!(g,val,id)
end

"""
    add_build_step!(model_graph,build_step,parent=-1)

add a build step to the model_graph, and add edges from all children of the
parent step to the child.
        [   parent_step   ]
           |           |
        [input] ... [input]
           |           |
        [    build_step   ]
"""
function add_build_step!(model_graph,build_step::BuildingStep,preceding_step=-1)
    node = add_node!(model_graph,build_step)
    for line in build_step.lines
        input = add_node!(model_graph,line)
        add_edge!(model_graph,input,node)
        add_edge!(model_graph,preceding_step,input)
    end
    add_edge!(model_graph,preceding_step,node) # Do I want this or not?
    node
end
function populate_model_subgraph!(model_graph,model::SubModelPlan)
    n = add_node!(model_graph,model)
    preceding_step = -1
    for build_step in model.steps
        preceding_step = add_build_step!(model_graph,build_step,preceding_step)
    end
    add_edge!(model_graph,preceding_step,n)
end

function construct_submodel_dependency_graph(model)
    g = NGraph{DiGraph,SubModelPlan,String}()
    for (k,m) in model.models
        n = add_node!(g,m,k)
    end
    for (k,m) in model.models
        for s in m.steps
            for line in s.lines
                if has_vertex(g,model_name(line))
                    add_edge!(g,model_name(line),k)
                end
            end
        end
    end
    return g
end

"""
Copy all submodel trees into the trees of their parent models.
"""
function copy_submodel_trees!(sched,model)
    sub_model_dependencies = construct_submodel_dependency_graph(model)
    for vp in topological_sort_by_dfs(sub_model_dependencies)
        k = get_vtx_id(sub_model_dependencies,vp)
        @assert has_vertex(sched,k) "SubModelPlan $k isn't in sched, but should be"
        for v in vertices(sched)
            node = get_node(sched,v)
            val = node_val(node)
            if isa(val,SubFileRef)
                if model_name(val) == k
                    sub_model_plan = duplicate_subtree!(sched,k,:in)
                    add_edge!(sched,sub_model_plan,v) # add before instead of replacing
                end
            end
        end
    end
    sched
end

"""
    construct_model_schedule(model)

Edges go forward in time.
"""
function construct_model_schedule(model)
    NODE_VAL_TYPE=Union{SubModelPlan,BuildingStep,SubFileRef}
    sched = MPDModelGraph{NODE_VAL_TYPE,String}()
    for (k,m) in model.models
        populate_model_subgraph!(sched,m)
    end
    copy_submodel_trees!(sched,model)
    return sched
end

"""
    extract_single_model(sched::S,model_key) where {S<:MPDModelGraph}

From a model schedule with (potentially) multiple distinct models, extract just
the model graph with root id `model_key`.
"""
function extract_single_model(sched::S,model_key) where {S<:MPDModelGraph}
    new_sched = S(id_generator=sched.id_generator)
    @assert has_vertex(sched,model_key)
    root = get_vtx(sched,model_key)
    add_node!(new_sched,get_node(sched,root),get_vtx_id(sched,root))
    for edge in edges(reverse(bfs_tree(sched,root;dir=:in)))
        src_id = get_vtx_id(sched,edge.src)
        dst_id = get_vtx_id(sched,edge.dst)
        if !has_vertex(new_sched,src_id)
            transplant!(new_sched,sched,src_id)
        end
        if !has_vertex(new_sched,dst_id)
            transplant!(new_sched,sched,dst_id)
        end
        add_edge!(new_sched,src_id,dst_id)
    end
    new_sched
end

GraphUtils.validate_edge(::SubModelPlan,::SubFileRef) = true
GraphUtils.validate_edge(::BuildingStep,::SubModelPlan) = true
GraphUtils.validate_edge(::BuildingStep,::BuildingStep) = true
GraphUtils.validate_edge(::BuildingStep,::SubFileRef) = true
GraphUtils.validate_edge(::SubFileRef,::BuildingStep) = true

GraphUtils.eligible_successors(::SubFileRef) = Dict(BuildingStep=>1)
GraphUtils.eligible_predecessors(::SubFileRef) = Dict(BuildingStep=>1,SubModelPlan=>1)
GraphUtils.required_successors(::SubFileRef) = Dict(BuildingStep=>1)
GraphUtils.required_predecessors(::SubFileRef) = Dict()

GraphUtils.eligible_successors(::SubModelPlan) = Dict(SubFileRef=>1)
GraphUtils.eligible_predecessors(::SubModelPlan) = Dict(BuildingStep=>1)
GraphUtils.required_successors(::SubModelPlan) = Dict()
GraphUtils.required_predecessors(::SubModelPlan) = Dict(BuildingStep=>1)

GraphUtils.eligible_successors(::BuildingStep) = Dict(SubFileRef=>typemax(Int),SubModelPlan=>1,BuildingStep=>1)
GraphUtils.eligible_predecessors(n::BuildingStep) = Dict(SubFileRef=>n_lines(n),BuildingStep=>1)
GraphUtils.required_successors(::BuildingStep) = Dict(Union{SubModelPlan,BuildingStep}=>1)
GraphUtils.required_predecessors(n::BuildingStep) = Dict(SubFileRef=>n_lines(n))

"""
    construct_assembly_graph(model)

Construct an assembly graph, where each `SubModelPlan` has an outgoing edge to
each `SubFileRef` pointing to one of its components.
"""
function construct_assembly_graph(model)
    NODE_VAL_TYPE=Union{SubModelPlan,SubFileRef}
    model_graph = MPDModelGraph{NODE_VAL_TYPE,String}()
    for (k,m) in model.models
        n = add_node!(model_graph,m,k)
        for s in m.steps
            for line in s.lines
                np = add_node!(model_graph,line) #,id_generator(line.file))
                add_edge!(model_graph,n,np)
            end
        end
    end
    return model_graph
end


end
