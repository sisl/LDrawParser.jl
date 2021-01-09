module LDrawParser

using LightGraphs
using GraphUtils
using GeometryBasics
using Rotations, CoordinateTransformations
using Parameters
using Logging
using StaticArrays

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
    return nothing
end

"""
    FILE_TYPE

All LDraw files carry the LDR (default), DAT or MPD extension.

Official Parts
Part | Subpart | Primitive | 8_Primitive | 48_Primitive | Shortcut
Unofficial Parts
Unofficial_Part| Unofficial_Subpart | Unofficial_Primitive |
Unofficial_8_Primitive | Unofficial_48_Primitive | Unofficial_Shortcut

The file type is usually prefaced in one of the following ways
    0 !LDRAW_ORG <type> (qualifier(s)) (update-tag)
    0 LDRAW_ORG <type> update-tag
    0 Official LCAD <type> update-tag
    0 Unofficial <type>
    0 Un-official <type>
"""
@enum FILE_TYPE begin
    MODEL
    PART
    SUBPART
    PRIMITIVE
    SHORTCUT
    NONE_FILE_TYPE
end

const FILE_TYPE_HEADERS = Set{String}([
    "!LDRAW_ORG",
    "LDRAW_ORG",
    "OFFICIAL LCAD",
    "OFFICIAL",
    "UNOFFICIAL",
    "UN-OFFICIAL"
])
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
parse_file_type(k::AbstractString) = get(FILE_TYPE_DICT,uppercase(k), NONE_FILE_TYPE)

"""
    COMMAND_CODE

The line type of a line is the first number on the line. The line types are:
0. META          # 0 !<META command> <additional parameters>
1. SUB_FILE_REF  # 1 <colour> x y z a b c d e f g h i <file>
2. LINE          # 2 <colour> x1 y1 z1 x2 y2 z2
3. TRIANGLE      # 3 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3
4. QUADRILATERAL # 4 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
5. OPTIONAL_LINE # 5 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
"""
@enum COMMAND_CODE begin
    META          = 0 # 0 !<META command> <additional parameters>
    SUB_FILE_REF  = 1 # 1 <colour> x y z a b c d e f g h i <file>
    LINE          = 2 # 2 <colour> x1 y1 z1 x2 y2 z2
    TRIANGLE      = 3 # 3 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3
    QUADRILATERAL = 4 # 4 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
    OPTIONAL_LINE = 5 # 5 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
end
parse_command_code(k::AbstractString) = COMMAND_CODE(parse(Int,k))

"""
    META_COMMAND

0 !<META command> <additional parameters>
- `!` is used to positively identify this as a META command. (Note: A few
    official meta commands do not start with a ! in order to preserve backwards compatibility, however, all new official META commands must start with a ! and it is strongly recommended that new unofficial meta-commands also start with a !)
- `<META command>` is any string in all caps
- `<additional parameters>` is any string. Note that if a META command does not
    require any additional parameter, none should be given.
"""
@enum META_COMMAND begin
    FILE
    NAME
    STEP
    ROTSTEP_BEGIN # ROTSTEP (<x-angle> <y-angle> <z-angle> [(REL| ADD | ABS)] | END)
    ROTSTEP_END
    FILE_TYPE_DECLARATION
    OTHER_META_COMMAND
end

const META_COMMAND_DICT = Dict{String,META_COMMAND}(
    "FILE"          =>FILE,
    "STEP"          =>STEP,
    "ROTSTEP"       =>ROTSTEP_BEGIN,
    "ROTSTEP END"   =>ROTSTEP_END,
    "NAME"          =>NAME,
    "NAME:"         =>NAME,
    [k=>FILE_TYPE_DECLARATION for k in FILE_TYPE_HEADERS]...
)
parse_meta_command(k::AbstractString) = get(META_COMMAND_DICT, uppercase(k), OTHER_META_COMMAND)

@enum ROTATION_MODE begin
    REL
    ADD
    ABS
end
const ROTATION_MODE_DICT = Dict{String,ROTATION_MODE}(
    "REL"=>REL,
    "ADD"=>ADD,
    "ABS"=>ABS,
)
parse_rotation_mode(k::AbstractString) = get(ROTATION_MODE_DICT,uppercase(k),REL)

function parse_line(line)
    if Base.Sys.isunix()
        line = replace(line,"\\"=>"/") # switch from Windows directory delimiters to Unix
    end
    split_line = split(line)
    return split_line
end
const SplitLine = Vector{A} where {A<:AbstractString}
for op in [:parse_file_type, :parse_command_code]
    @eval $op(split_line::SplitLine) = $op(split_line[1])
end

function parse_meta_command(split_line::SplitLine)
    if split_line[1] == "0"
        return parse_meta_command(split_line[2:end])
    end
    cmd = parse_meta_command(split_line[1])
    if cmd == ROTSTEP_BEGIN
        if parse_meta_command(join(split_line[1:2]," ")) == ROTSTEP_END
            cmd = ROTSTEP_END
            # insert!(split_line,2,join(split_line[1:2]," "))
            # deleteat!(split_line,3)
            # deleteat!(split_line,3)
        end
    end
    return cmd
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
function build_transform(ref::SubFileRef)
    # @warn "Need to account for the weird LDraw coordinate system at some point"
    Translation(ref.pos[1],ref.pos[2],ref.pos[3]) ∘ LinearMap(ref.rot)
end
function SubFileRef(ref::SubFileRef,T::AffineMap)
    new_ref = SubFileRef(
        ref.color,
        Point3D(T.translation...),
        T.linear,
        ref.file
    )
end

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
function set_status!(t::Toggle,val=true)
    t.status = val
end
get_status(t::Toggle) = copy(t.status)

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
function extract_surface_geometry(m::DATModel)
    elements = Vector{GeometryBasics.Ngon}()
    for vec in (m.triangle_geometry,m.quadrilateral_geometry)
        for e in vec
            push!(elements,e.geom)
        end
    end
    elements
end
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
function incorporate_geometry!(m::DATModel,ref::SubFileRef,child::DATModel,scale=1.0)
    t = build_transform(ref)
    incorporate_geometry!(m,child,t,scale)
end
function incorporate_geometry!(m::DATModel,child::DATModel,t,scale=1.0)
    # @info "incorporating geometry from $(child.name) into $(m.name)"
    for (parent_geometry,child_geometry) in zip(
            (m.line_geometry, m.triangle_geometry, m.quadrilateral_geometry,
                m.optional_line_geometry),
            (child.line_geometry, child.triangle_geometry, child.quadrilateral_geometry,
                child.optional_line_geometry)
        )
        for element in child_geometry
            push!(parent_geometry, t(element)*scale)
        end
    end
    return m
end
function DATModel(part::DATModel,T,scale=1.0)
    new_part = DATModel(part.name)
    incorporate_geometry!(new_part,part,T,scale)
    set_status!(new_part.populated,get_status(part.populated))
    new_part
end

"""
    MPDModel

The MPD model stores the information contained in a .mpd or .ldr file. This
includes a submodel tree (stored implicitly in a dictionary that maps model_name
to SubModelPlan) and a part list. The first model in MPDModel.models is the main
model. All the following are submodels of that model and/or each other.
"""
struct MPDModel #<: AbstractCustomNEDiGraph{CustomNode{Union{SubModelPlan,DATModel},String},CustomEdge{SubModelRef,String},String}
    models      ::Dict{String,SubModelPlan} # each file is a list of steps
    parts       ::Dict{String,DATModel}
    sub_parts   ::Dict{String,DATModel}
    # part_graph  ::NEGraph{DiGraph,Union{SubModelPlan,DATModel},SubFileRef,String}
    # graph       ::DiGraph
    # nodes       ::Vector{CustomNode{Union{SubModelPlan,DATModel},String}}
    # vtx_map     ::Dict{String,Int}
    # vtx_ids     ::Vector{String}
    # inedges     ::Vector{Dict{Int,CustomEdge{SubModelRef,String}}}
    # outedges    ::Vector{Dict{Int,CustomEdge{SubModelRef,String}}}
    MPDModel() = new(
        Dict{String,SubModelPlan}(),
        Dict{String,DATModel}(),
        Dict{String,DATModel}(),
        # NEGraph{DiGraph,DATModel,SubFileRef,String}()
        # DiGraph(),
        # Vector{CustomNode{Union{SubModelPlan,DATModel},String}}(),
        # Dict{String,Int}(),
        # Vector{String}(),
        # Vector{Dict{Int,CustomEdge{SubModelRef,String}}}(),
        # Vector{Dict{Int,CustomEdge{SubModelRef,String}}}(),
    )
end
function get_part(m::MPDModel,k)
    if haskey(m.parts,k)
        return m.parts[k]
    elseif haskey(m.sub_parts,k)
        return m.sub_parts[k]
    end
    return nothing
end
has_part(m::MPDModel,k) = haskey(m.parts,k) || haskey(m.sub_parts,k)
function set_part!(m::MPDModel,part,k=part.name)
    if haskey(m.sub_parts,k)
        m.sub_parts[k] = part
    else
        m.parts[k] = part
    end
    part
end
function add_part!(m::MPDModel,k)
    @assert !has_part(m,k)
    m.parts[k] = DATModel(k)
end
function add_sub_part!(m::MPDModel,k)
    @assert !has_part(m,k)
    m.sub_parts[k] = DATModel(k)
end
part_keys(m::MPDModel) = keys(m.parts)
sub_part_keys(m::MPDModel) = keys(m.sub_parts)
all_part_keys(m::MPDModel) = Base.Iterators.flatten((part_keys(m),sub_part_keys(m)))

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
    rot_stack::Vector{SMatrix{3,3,Float64}} = [one(SMatrix{3,3,Float64})]
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
function set_active_model!(model::MPDModel,state,name)
    # @assert !haskey(model.models,name)
    if !haskey(model.models,name)
        model.models[name] = SubModelPlan(name)
    else
        @debug "$name is already in model!"
    end
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
    # @assert !isempty(model.parts)
    @assert has_part(model,state.active_part)
    # return model.parts[state.active_part]
    return get_part(model,state.active_part)
end
function set_active_part!(model::MPDModel,state,name)
    # @assert !has_part(model,name) "$name is already a part in model!"
    if !has_part(model,name)
        add_part!(model,name)
    else
        @debug "$name is already a part in model!"
    end
    @debug "Active part = $name"
    return MPDModelState(state,active_part=name)
end
function add_sub_file_placement!(model::MPDModel,state,ref)
    # TODO figure out how to place a subfile that is not part of a build step,
    # but is rather (presumably) a subfile of a .dat model
    if state.file_type == MODEL
        if !isempty(state.active_model) # != ""
            push!(active_building_step(model,state),ref)
        end
    else
        if !isempty(state.active_part) # != ""
            push!(active_part(model,state).subfiles,ref)
        end
    end
    if !has_part(model,ref.file)
        if isempty(state.active_part)
            add_part!(model,ref.file)
        else
            add_sub_part!(model,ref.file)
        end
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
        # try
            if length(line) == 0
                continue
            end
            split_line = parse_line(line)
            if isempty(split_line[1])
                continue
            end
            code = parse_command_code(split_line)
            @debug "LINE: $line"
            @debug "code: $code"
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
            elseif code == OPTIONAL_LINE
                state = read_optional_line!(model,state,split_line)
            end
        # catch e
        #     bt = catch_backtrace()
        #     showerror(stdout,e,bt)
        #     rethrow(e)
        # end
    end
    return model
end
function parse_ldraw_file!(model,filename::String,args...)
    open(find_part_file(filename),"r") do io
        parse_ldraw_file!(model,io,args...)
    end
end
parse_ldraw_file(io,args...) = parse_ldraw_file!(MPDModel(),io,args...)
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
        @debug "Returning because length(line) < 2. Usually this means the end of the file"
        return state
    end
    # cmd = line[2]
    cmd = parse_meta_command(line[2:end])
    @debug "cmd: $cmd"
    if cmd == FILE || cmd == NAME
        filename = join(line[3:end]," ")
        ext = lowercase(splitext(filename)[2])
        if ext == ".dat"
            state = set_active_part!(model,state,filename)
            if state.file_type == NONE_FILE_TYPE
                state.file_type = PART
            end
        elseif ext == ".mpd" || ext == ".ldr"
            state = set_active_model!(model,state,filename)
            if state.file_type == NONE_FILE_TYPE
                state.file_type = MODEL
            end
        end
        @debug "file = $filename"
    elseif cmd == STEP
        set_new_active_building_step!(model,state)
    # elseif cmd == ROTSTEP_BEGIN
    #     rx,ry,rz = [parse(Float64,line[3]),parse(Float64,line[4]),parse(Float64,line[5])]
    #     rot_mode = parse_rotation_mode(line[6])
    #     rmat = RotMatrix(RotXYZ(rx,ry,rz)).mat
    #     if rot_mode == ABS
    #         empty!(state.rot_stack)
    #         push!(state.rot_stack, rmat)
    #     elseif rot_mode == REL
    #         @warn "Need to be sure that RotXYZ does things in the right order"
    #         push!(state.rot_stack, rmat)
    #     elseif rot_mode == ADD
    #         push!(state.rot_stack, rmat)
    #     end
    # elseif cmd == ROTSTEP_END
    #     if length(state.rot_stack) > 1
    #         pop!(state.rot_stack) # remove the last
    #     else
    #         state.rot_stack[1] = one(eltype(state.rot_stack))
    #     end
    elseif cmd == FILE_TYPE_DECLARATION
        state.file_type = parse_file_type(line[3])
        if state.file_type == NONE_FILE_TYPE
            @debug "file type not resolved on line : $line"
        end
        @debug "file_type=$(state.file_type)"
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

For reading lines of type OPTIONAL_LINE
"""
function read_optional_line!(model,state,line)
    @assert parse_command_code(line[1]) == OPTIONAL_LINE
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

function populate_part_geometry!(model,frontier=Set(collect(part_keys(model))))
    explored = Set{String}()
    while !isempty(frontier)
        subcomponent = pop!(frontier)
        push!(explored,subcomponent)
        partfile = find_part_file(subcomponent)
        if partfile === nothing
            @warn "Can't find file $subcomponent. Skipping..."
            continue
        end
        parse_ldraw_file!(model,partfile,MPDModelState(active_part=subcomponent))
        # for k in keys(model.parts)
        for k in all_part_keys(model)
            if !(k in explored)
                push!(frontier,k)
            end
        end
    end
    # go back through and recursively load geometry from subcomponents
    frontier = explored
    explored = Set{String}()
    while !isempty(frontier)
        name = pop!(frontier)
        part = get_part(model,name)
        recurse_part_geometry!(model,part,explored)
        setdiff!(frontier,explored)
    end
    model
end
function recurse_part_geometry!(model,part::DATModel,explored)
    if get_status(part.populated)
        push!(explored,part.name)
        return part
    end
    for ref in part.subfiles
        if has_part(model,ref.file)
            subpart = get_part(model,ref.file)
            if !(ref.file in explored)
                recurse_part_geometry!(model,subpart,explored)
            end
            incorporate_geometry!(part,ref,subpart)
        end
    end
    set_status!(part.populated,true)
    push!(explored,part.name)
    part
end

const LDRAW_BASE_FRAME = SMatrix{3,3,Float64}(
    1.0,  0.0,  0.0,
    0.0,  0.0,  -1.0,
    0.0,  1.0,  0.0
)

function (t::AffineMap)(g::G) where {G<:GeometryBasics.Ngon}
    G(map(t,g.points))
end
(t::AffineMap)(g::G) where {G<:NgonElement} = G(g.color,t(g.geom))
(t::AffineMap)(g::G) where {G<:OptionalLineElement} = G(g.color,t(g.geom),t(g.control_pts))
function Base.:(*)(r::Rotation,g::G) where {G<:GeometryBasics.Ngon}
    G(map(p->r*p,g.points))
end
function Base.:(*)(g::G,x::Float64) where {G<:GeometryBasics.Ngon}
    G(map(p->p*x,g.points))
end
Base.:(*)(g::G,x::Float64) where {G<:NgonElement} = G(g.color,g.geom*x)
Base.:(*)(g::G,x::Float64) where {G<:OptionalLineElement} = G(g.color,g.geom*x,g.control_pts*x)
function scale_translation(T::AffineMap,scale::Float64)
    compose(Translation(scale*T.translation...), LinearMap(T.linear))
end

"""
    change_coordinate_system!(model::MPDModel,T)

Transform the coordinate system of the entire model
"""
function change_coordinate_system!(model::MPDModel,T,scale=1.0)
    Tinv = inv(T)
    for (k,m) in model.models
        for step in m.steps
            for i in 1:length(step.lines)
                ref = step.lines[i]
                t = build_transform(ref)
                new_t = scale_translation(T ∘ t ∘ Tinv,scale)
                step.lines[i] = SubFileRef(ref,new_t)
            end
        end
    end
    for k in collect(all_part_keys(model))
        part = get_part(model,k)
        new_part = DATModel(part,T,scale)
        set_part!(model,new_part,k)
    end
    return model
end

function GeometryBasics.decompose(
        ::Type{TriangleFace{Int}},
        n::GeometryBasics.Ngon{3,Float64,N,Point{3,Float64}}) where {N}
    return SVector{N-1,TriangleFace{Int}}(
        TriangleFace{Int}(1,i,i+1) for i in 1:N-1
    )
end
function GeometryBasics.decompose(
        ::Type{Point{3,Float64}},
        n::GeometryBasics.Ngon)
    return n.points
end
GeometryBasics.faces(n::GeometryBasics.Ngon{3,Float64,4,Point{3,Float64}}) = [
    # QuadFace{Int}(1,2,3,4)
    TriangleFace{Int}(1,2,3),TriangleFace{Int}(1,3,4)
]
GeometryBasics.faces(n::GeometryBasics.Ngon{3,Float64,3,Point{3,Float64}}) = [
    TriangleFace{Int}(1,2,3)
]
GeometryBasics.coordinates(n::GeometryBasics.Ngon{3,Float64,N,Point{3,Float64}}) where {N} = Vector(n.points)

function GeometryBasics.coordinates(v::AbstractVector{G}) where {N,G<:GeometryBasics.Ngon{3,Float64,N,Point{3,Float64}}}
    vcat(map(coordinates,v)...)
end
function GeometryBasics.faces(v::AbstractVector{G}) where {N,G<:GeometryBasics.Ngon{3,Float64,N,Point{3,Float64}}}
    vcat(map(i->map(f->f .+ ((i-1)*N),faces(v[i])),1:length(v))...)
end
function GeometryBasics.faces(v::AbstractVector{G}) where {G<:GeometryBasics.Ngon}
    face_vec = Vector{TriangleFace{Int}}()
    i = 0
    for element in v
        append!(face_vec, map(f->f.+i,faces(element)))
        i = face_vec[end].data[3]
    end
    return face_vec
end
function GeometryBasics.coordinates(v::AbstractVector{G}) where {G<:GeometryBasics.Ngon}
    coords = Vector{Point{3,Float64}}()
    for element in v
        append!(coords, coordinates(element))
    end
    return coords
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
