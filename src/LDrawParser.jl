module LDrawParser

using GeometryBasics
using Rotations
using CoordinateTransformations
using Parameters
using StaticArrays
using Colors
using ProgressMeter
using LinearAlgebra: det

export
    get_part_library_dir,
    set_part_library_dir!,
    find_part_file,
    SubModelPlan,
    DATModel,
    SubFileRef,
    BuildingStep,
    MPDModel,
    model_name,
    has_model,
    get_model,
    has_part,
    get_part,
    parse_ldraw_file!,
    parse_ldraw_file,
    populate_part_geometry!,
    ldraw_base_transform,
    change_coordinate_system!,
    extract_geometry,
    build_transform

mutable struct Toggle
    status::Bool
end
function set_toggle_status!(t::Toggle, val=true)
    t.status = val
end
get_toggle_status(t::Toggle) = copy(t.status)

global PART_LIBRARY_DIR = joinpath(homedir(), "Documents/ldraw")
get_part_library_dir() = deepcopy(PART_LIBRARY_DIR)
function set_part_library_dir!(path)
    PART_LIBRARY_DIR = path
end

global FILE_PATH_CACHE = Dict{String,String}()
get_file_path_cache() = FILE_PATH_CACHE
function try_find_part_file!(name, library=get_part_library_dir())
    cache = get_file_path_cache()
    if haskey(cache, name)
        @debug "found $name in FILE_PATH_CACHE"
        return cache[name]
    else
        filepath = find_part_file(name, library)
        if !(filepath === nothing)
            cache[name] = filepath
            cache[filepath] = filepath
            return filepath
        else
            cache[name] = name
        end
    end
    return name
end

"""
    find_part_file(name,library=get_part_library_dir())

Try to find a file with name `name`, and return that file's path if found.
"""
function find_part_file(name, library=get_part_library_dir())
    if isfile(name)
        return name
    end
    for (root, dirs, _) in walkdir(library)
        for dir in dirs
            d = joinpath(root, dir)
            for p in [joinpath(d, name), joinpath(d, lowercase(name))]
                if isfile(p)
                    return p
                end
            end
        end
    end
    @debug "Part file $name not found in library at $library"
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
    "MODEL" => MODEL,
    "PART" => PART,
    "UNOFFICIAL_PART" => PART,
    "SUBPART" => SUBPART,
    "UNOFFICIAL_SUBPART" => SUBPART,
    "PRIMITIVE" => PRIMITIVE,
    "8_PRIMITIVE" => PRIMITIVE,
    "48_PRIMITIVE" => PRIMITIVE,
    "UNOFFICIAL_PRIMITIVE" => PRIMITIVE,
    "UNOFFICIAL_8_PRIMITIVE" => PRIMITIVE,
    "UNOFFICIAL_48_PRIMITIVE" => PRIMITIVE,
    "UNOFFICIAL_SHORTCUT" => PRIMITIVE,
    "SHORTCUT" => SHORTCUT,
)
parse_file_type(k::AbstractString) = get(FILE_TYPE_DICT, uppercase(k), NONE_FILE_TYPE)

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
    META = 0 # 0 !<META command> <additional parameters>
    SUB_FILE_REF = 1 # 1 <colour> x y z a b c d e f g h i <file>
    LINE = 2 # 2 <colour> x1 y1 z1 x2 y2 z2
    TRIANGLE = 3 # 3 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3
    QUADRILATERAL = 4 # 4 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
    OPTIONAL_LINE = 5 # 5 <colour> x1 y1 z1 x2 y2 z2 x3 y3 z3 x4 y4 z4
end
parse_command_code(k::AbstractString) = COMMAND_CODE(parse(Int, k))

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
    COLORDEF
end

const META_COMMAND_DICT = Dict{String,META_COMMAND}(
    "FILE" => FILE,
    "STEP" => STEP,
    "ROTSTEP" => ROTSTEP_BEGIN,
    "ROTSTEP END" => ROTSTEP_END,
    "NAME" => NAME,
    "NAME:" => NAME,
    [k => FILE_TYPE_DECLARATION for k in FILE_TYPE_HEADERS]...,
    "COLOUR" => COLORDEF,
    "COLOR" => COLORDEF,
    "!COLOUR" => COLORDEF,
    "!COLOR" => COLORDEF,
)
parse_meta_command(k::AbstractString) = get(META_COMMAND_DICT, uppercase(k), OTHER_META_COMMAND)

@enum ROTATION_MODE begin
    REL
    ADD
    ABS
end
const ROTATION_MODE_DICT = Dict{String,ROTATION_MODE}(
    "REL" => REL,
    "ADD" => ADD,
    "ABS" => ABS,
)
parse_rotation_mode(k::AbstractString) = get(ROTATION_MODE_DICT, uppercase(k), REL)

function parse_line(line)
    if Base.Sys.isunix()
        line = replace(line, "\\" => "/") # switch from Windows directory delimiters to Unix
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
    if cmd == ROTSTEP_BEGIN # NOTE not necessary, as it only affects the VIEW (not the model)
        if parse_meta_command(join(split_line[1:2], " ")) == ROTSTEP_END
            cmd = ROTSTEP_END
        end
    end
    return cmd
end

const Point3D = Point{3,Float64}

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

    function SubFileRef(color, pos, rot, file; ignore_rotation_determinant)
        if !ignore_rotation_determinant && det(rot) < 0
            @warn "Determinant of rotation matrix is negative! Component referenced: $file"
        end
        return new(color, pos, rot, file)
    end
end
Base.summary(s::SubFileRef) = string("SubFileRef → ", s.file, " : ", s.pos)
model_name(r::SubFileRef) = r.file
function build_transform(ref::SubFileRef)
    Translation(ref.pos[1], ref.pos[2], ref.pos[3]) ∘ LinearMap(ref.rot)
end
function SubFileRef(ref::SubFileRef, T::AffineMap; kwargs...)
    new_ref = SubFileRef(ref.color, Point3D(T.translation...), T.linear, ref.file; kwargs...)
end

"""
    BuildingStep

Represents a sequence of part placements that make up a building step in a LDraw
file.
"""
struct BuildingStep
    parent::String # points to the SubModelPlan to which it belongs
    lines::Vector{SubFileRef}
end
Base.push!(step::BuildingStep, ref::SubFileRef) = push!(step.lines, ref)
n_lines(s::BuildingStep) = length(s.lines)
BuildingStep(p::String) = BuildingStep(p, Vector{SubFileRef}())
BuildingStep(step::BuildingStep, parent::String) = BuildingStep(parent, step.lines)

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
        Vector{BuildingStep}([BuildingStep(name)])
    )
end
model_name(r::SubModelPlan) = r.name
n_build_steps(m::SubModelPlan) = length(m.steps)
n_assembly_components(m::SubModelPlan) = sum(map(n_lines, m.steps))
BuildingStep(p::SubModelPlan) = BuildingStep(model_name(p))
Base.summary(n::SubModelPlan) = string("SubModelPlan: ", model_name(n), ": ",
    n_build_steps(n), " building steps, ", n_assembly_components(n), " components")


const Quadrilateral{Dim,T} = GeometryBasics.Ngon{Dim,T,4,Point{Dim,T}}
set_status!(t::Toggle, val) = set_toggle_status!(t, val)
get_status(t::Toggle) = get_toggle_status(t)

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
function Base.summary(d::DATModel)
    string("DATModel",
        "\n\t", "$(d.name)",
        "\n\t", "line_geometry:", "$(length(d.line_geometry))",
        "\n\t", "triangle_geometry:", "$(length(d.triangle_geometry))",
        "\n\t", "quad_geometry:", "$(length(d.quadrilateral_geometry))",
        "\n\t", "optional_line_geometry:", "$(length(d.optional_line_geometry))",
        "\n\t", "sub_files:", "$(length(d.subfiles))",
        "\n\t", "populated: ", "$(d.populated)")
end
model_name(r::DATModel) = r.name
function extract_surface_geometry(m::DATModel)
    elements = Vector{GeometryBasics.Ngon}()
    for vec in (m.triangle_geometry, m.quadrilateral_geometry)
        for e in vec
            push!(elements, e.geom)
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
            push!(elements, e.geom)
        end
    end
    elements
end
function extract_points(m::DATModel)
    pts = Vector{Point3{Float64}}()
    for e in extract_geometry(m)
        for pt in coordinates(e) #.points
            push!(pts, pt)
        end
    end
    pts
end
function geometry_iterator(m::DATModel)
    Base.Iterators.flatten(
        (m.line_geometry,
        m.triangle_geometry,
        m.quadrilateral_geometry,
        m.optional_line_geometry)
    )
end
points_iterator(m::DATModel) = Base.Iterators.flatten(map(e -> e.geom.points, geometry_iterator(m)))
GeometryBasics.coordinates(m::DATModel) = points_iterator(m)
function incorporate_geometry!(m::DATModel, ref::SubFileRef, child::DATModel, scale=1.0)
    t = build_transform(ref)
    incorporate_geometry!(m, child, t, scale)
end
function incorporate_geometry!(m::DATModel, child::DATModel, t, scale=1.0)
    @info "incorporating geometry from $(child.name) into $(m.name)"
    for (parent_geometry, child_geometry) in zip(
        (m.line_geometry, m.triangle_geometry, m.quadrilateral_geometry,
            m.optional_line_geometry),
        (child.line_geometry, child.triangle_geometry, child.quadrilateral_geometry,
            child.optional_line_geometry)
    )
        for element in child_geometry
            push!(parent_geometry, t(element) * scale)
        end
    end
    return m
end
function DATModel(part::DATModel, T, scale=1.0)
    new_part = DATModel(part.name)
    incorporate_geometry!(new_part, part, T, scale)
    set_status!(new_part.populated, get_status(part.populated))
    new_part
end

"""
    MPDModel

The MPD model stores the information contained in a .mpd or .ldr file. This
includes a submodel tree (stored implicitly in a dictionary that maps model_name
to SubModelPlan) and a part list. The first model in MPDModel.models is the main
model. All the following are submodels of that model and/or each other.
"""
@with_kw_noshow struct MPDModel #<: AbstractCustomNEDiGraph{CustomNode{Union{SubModelPlan,DATModel},String},CustomEdge{SubModelRef,String},String}
    models::Dict{String,SubModelPlan} = Dict{String,SubModelPlan}() # each file is a list of steps
    parts::Dict{String,DATModel} = Dict{String,DATModel}()
    sub_parts::Dict{String,DATModel} = Dict{String,DATModel}()
end
has_part(m::MPDModel, k) = haskey(m.parts, k) || haskey(m.sub_parts, k)
function get_part(m::MPDModel, k)
    if haskey(m.parts, k)
        return m.parts[k]
    elseif haskey(m.sub_parts, k)
        return m.sub_parts[k]
    end
    return nothing
end
has_model(m::MPDModel, k) = haskey(m.models, k)
get_model(m::MPDModel, k) = get(m.models, k, nothing)
function set_part!(m::MPDModel, part, k=part.name)
    if haskey(m.sub_parts, k)
        m.sub_parts[k] = part
    else
        m.parts[k] = part
    end
    part
end
function add_part!(m::MPDModel, k)
    @assert !has_part(m, k)
    m.parts[k] = DATModel(k)
end
function add_sub_part!(m::MPDModel, k)
    @assert !has_part(m, k)
    m.sub_parts[k] = DATModel(k)
end
part_keys(m::MPDModel) = keys(m.parts)
sub_part_keys(m::MPDModel) = keys(m.sub_parts)
all_part_keys(m::MPDModel) = Base.Iterators.flatten((part_keys(m), sub_part_keys(m)))

points_to_part(m::MPDModel, ref::SubFileRef) = has_part(m, ref.file)
points_to_model(m::MPDModel, ref::SubFileRef) = has_model(m, ref.file)

@with_kw_noshow mutable struct MPDModelState
    file_type::FILE_TYPE = NONE_FILE_TYPE
    active_model::String = ""
    active_part::String = ""
    rot_stack::Vector{SMatrix{3,3,Float64}} = [one(SMatrix{3,3,Float64})]
end

Base.summary(s::MPDModelState) = string(
    "MPDModelState(file_type=$(s.file_type), active_model=$(s.active_model), active_part=$(s.active_part))")

update_state(state::MPDModelState) = MPDModelState(state) # TODO deal with single step macro commands, etc.
function active_building_step(submodel::SubModelPlan, state)
    @assert !isempty(submodel.steps)
    active_step = submodel.steps[end]
end
function active_submodel(model::MPDModel, state)
    @assert !isempty(model.models)
    return model.models[state.active_model]
end
function set_active_model!(model::MPDModel, state, name)
    if !has_model(model, name)
        model.models[name] = SubModelPlan(name)
    else
        @debug "$name is already in model!"
    end
    return MPDModelState(state, active_model=name)
end
function active_building_step(model::MPDModel, state)
    active_model = active_submodel(model, state)
    return active_building_step(active_model, state)
end
function set_new_active_building_step!(model::SubModelPlan)
    push!(model.steps, BuildingStep(model))
    return model
end
function set_new_active_building_step!(model::MPDModel, state)
    active_model = active_submodel(model, state)
    set_new_active_building_step!(active_model)
    return model
end
function active_part(model::MPDModel, state)
    # @assert !isempty(model.parts)
    @assert has_part(model, state.active_part) "has_part(model,$(state.active_part))"
    # return model.parts[state.active_part]
    return get_part(model, state.active_part)
end
function set_active_part!(model::MPDModel, state, name)
    # @assert !has_part(model,name) "$name is already a part in model!"
    if !has_part(model, name)
        add_part!(model, name)
    else
        @debug "$name is already a part in model!"
    end
    @debug "Active part = $name"
    return MPDModelState(state, active_part=name)
end
function add_sub_file_placement!(model::MPDModel, state, ref)
    # TODO figure out how to place a subfile that is not part of a build step,
    # but is rather (presumably) a subfile of a .dat model
    if state.file_type == MODEL
        if !isempty(state.active_model) # != ""
            push!(active_building_step(model, state), ref)
        end
    else
        if !isempty(state.active_part) # != ""
            push!(active_part(model, state).subfiles, ref)
        end
    end
    if !has_part(model, ref.file)
        if isempty(state.active_part)
            add_part!(model, ref.file)
        else
            add_sub_part!(model, ref.file)
        end
    end
    return state
end

"""
    preprocess_ldraw_file(io)

Return a set of part names that are masquerading as submodels.
"""
function preprocess_ldraw_file(io)
    state = MPDModelState()
    model = MPDModel()
    sneaky_parts = Set{String}()
    current_filename = nothing
    include_sub_file_ref = false
    for line in eachline(io)
        if length(line) == 0
            continue
        end
        split_line = parse_line(line)
        if isempty(split_line[1])
            continue
        end
        code = parse_command_code(split_line)
        if code == META
            @assert parse_command_code(split_line[1]) == META
            if length(split_line) < 2
                continue
            end
            cmd = parse_meta_command(split_line[2:end])
            if cmd == FILE || cmd == NAME
                current_filename = join(split_line[3:end], " ")
                include_sub_file_ref = false
                if current_filename[end-3:end] == ".dat"
                    include_sub_file_ref = true
                end
            end
        elseif code == LINE || code == TRIANGLE || code == QUADRILATERAL || code == OPTIONAL_LINE || (include_sub_file_ref && code == SUB_FILE_REF)
            if !(current_filename === nothing)
                push!(sneaky_parts, current_filename)
            end
        end
    end
    return sneaky_parts
end

"""
    parse_ldraw_file!

Args:
    - model: MPDModel
        The model into which the LDraw file will be parsed.
    - filename or IO: part filename
    - state: MPDModelState = MPDModelState()
        The state of the parser. This is used to keep track of the active model
        and active part.
Keyword Args:
    - sneaky_parts: Set{String} = Set{String}()
        Set of part names that are masquerading as submodels.
    - ignore_rotation_determinant: Bool = false
        If true, ignore the determinant of the rotation matrix. This is useful
        for parts that are not properly oriented in the LDraw library.
"""
function parse_ldraw_file!(
    model, io, state=MPDModelState();
    sneaky_parts=Set{String}(), ignore_rotation_determinant=false
)
    prog = ProgressMeter.Progress(countlines(io); desc="Processing file...", showspeed=true, barlen=50)
    seekstart(io)
    for line in eachline(io)
        next!(prog) # Should go at end, but we have a continue statement midway through
        if length(line) == 0
            continue
        end
        split_line = parse_line(line)
        if isempty(split_line) || isempty(split_line[1])
            continue
        end
        code = parse_command_code(split_line)
        @debug "LINE: $line"
        @debug "code: $code"
        if code == META
            state = read_meta_line!(model, state, split_line, sneaky_parts)
        elseif code == SUB_FILE_REF
            state = read_sub_file_ref!(model, state, split_line; ignore_rotation_determinant=ignore_rotation_determinant)
            # Geometry
        elseif code == LINE
            state = read_line!(model, state, split_line)
        elseif code == TRIANGLE
            state = read_triangle!(model, state, split_line)
        elseif code == QUADRILATERAL
            state = read_quadrilateral!(model, state, split_line)
        elseif code == OPTIONAL_LINE
            state = read_optional_line!(model, state, split_line)
        end
    end
    return model
end
function parse_ldraw_file!(model, filename::String, args...; kwargs...)
    open(find_part_file(filename), "r") do io
        parse_ldraw_file!(model, io, args...; kwargs...)
    end
end
"""
    parse_ldraw_file(filename::String, args...; kwargs...)

Parse an LDraw file and return an MPDModel.

Args:
    - filename: String
        The name of the LDraw file to parse.
Keyword Args:
    - ignore_rotation_determinant: Bool = false
        If true, ignore the determinant of the rotation matrix. This is useful
        for parts that are not properly oriented in the LDraw library.
"""
function parse_ldraw_file(io, args...; sneaky_parts=preprocess_ldraw_file(io), kwargs...)
    parse_ldraw_file!(MPDModel(), io, args...; sneaky_parts=sneaky_parts, kwargs...)
end
parse_color(c) = parse(Int, c)


"""
    read_meta_line(model,state,line)

Modifies the model and parser_state based on a META command. For example, the
FILE meta command indicates the beginning of a new file, so this creates a new
active model into which subsequent building steps will be placed.
The STEP meta command indicates the end of the current step, which prompts the
parser to close the current build step and begin a new one.
"""
function read_meta_line!(model, state, line, sneaky_parts=Set{String}())
    @assert parse_command_code(line[1]) == META
    if length(line) < 2
        @debug "Returning because length(line) < 2. Usually this means the end of the file"
        return state
    end
    # cmd = line[2]
    cmd = parse_meta_command(line[2:end])
    @debug "cmd: $cmd"
    if cmd == FILE || cmd == NAME
        filename = join(line[3:end], " ")
        filename = try_find_part_file!(filename)
        ext = lowercase(splitext(filename)[2])
        if filename in sneaky_parts
            @warn "filename in sneaky parts!" filename
        end
        if ext == ".dat" || (filename in sneaky_parts)
            state = set_active_part!(model, state, filename)
            if state.file_type == NONE_FILE_TYPE
                state.file_type = PART
            end
        elseif ext == ".mpd" || ext == ".ldr"
            state = set_active_model!(model, state, filename)
            if state.file_type == NONE_FILE_TYPE
                state.file_type = MODEL
            end
        end
        @debug "file = $filename"
    elseif cmd == STEP
        set_new_active_building_step!(model, state)
    elseif cmd == FILE_TYPE_DECLARATION
        state.file_type = parse_file_type(line[3])
        if state.file_type == NONE_FILE_TYPE
            @debug "file type not resolved on line : $line"
        end
        @debug "file_type=$(state.file_type)"
    elseif cmd == COLORDEF
        # add color definition to global color dict
        parse_color_def!(line)
    else
        # TODO Handle other META commands, especially BFC
    end
    return state
end

global COLOR_DICT = Dict{Int,ColorAlpha}()
color_dict_is_loaded() = !isempty(COLOR_DICT)


function parse_color_def!(line)
    @assert parse_command_code(line[1]) == META
    @assert parse_meta_command(line[2]) == COLORDEF
    color_code = nothing
    color_val = nothing
    alpha_val = 1.0
    val, line_iter = Base.Iterators.peel(line)
    while !isempty(line_iter)
        if val == "CODE"
            val, line_iter = Base.Iterators.peel(line_iter)
            color_code = parse(Int, val)
        elseif val == "VALUE"
            val, line_iter = Base.Iterators.peel(line_iter)
            color_val = parse(Colorant, val)
        elseif val == "ALPHA"
            val, line_iter = Base.Iterators.peel(line_iter)
            alpha_val = parse(Int, val) / 256.0
        else
            val, line_iter = Base.Iterators.peel(line_iter)
        end
    end
    if !(color_code === nothing) && !(color_val === nothing)
        global COLOR_DICT
        # @show color_val, alpha_val
        COLOR_DICT[color_code] = alphacolor(color_val, alpha_val)
    end
end

"""
    load_color_dict!(path=joinpath(get_part_library_dir(),"LDConfig.ldr")))

Load dictionary mapping Integer code to color.
"""
function load_color_dict!(paths=
[
    joinpath(get_part_library_dir(), "LDConfig.ldr"),
    joinpath(get_part_library_dir(), "LDCfgalt.ldr"),
],
)
    for path in paths
        open(path) do io
            for line in eachline(io)
                if length(line) <= 1
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
                    if parse_meta_command(split_line) == COLORDEF
                        parse_color_def!(split_line)
                    end
                end
            end
        end
    end
end

"""
    get_color_dict()

get dictionary mapping Integer code to color.
"""
function get_color_dict()
    if !color_dict_is_loaded()
        load_color_dict!()
    end
    deepcopy(COLOR_DICT)
end



"""
    read_sub_file_ref

Receives a SUB_FILE_REF line (with the leading SUB_FILE_REF id stripped)
"""
function read_sub_file_ref!(model, state, line; kwargs...)
    @assert parse_command_code(line[1]) == SUB_FILE_REF
    @assert length(line) >= 15 "$line"
    color = parse_color(line[2])
    # coordinate of part
    x, y, z = parse.(Float64, line[3:5])
    # rotation of part
    rot_mat = collect(transpose(reshape(parse.(Float64, line[6:14]), 3, 3)))
    file = join(line[15:end], " ")
    file = try_find_part_file!(file)
    # TODO add a line struct to the model
    ref = SubFileRef(color, Point3D(x, y, z), Mat{3,3,Float64}(rot_mat), file; kwargs...)
    add_sub_file_placement!(model, state, ref)
    # push!(model.sub_file_refs,ref)
    return state
end

"""
    read_line!

For reading lines of type LINE
"""
function read_line!(model, state, line)
    @assert parse_command_code(line[1]) == LINE
    @assert length(line) == 8 "$line"
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64, line[3:5]))
    p2 = Point3D(parse.(Float64, line[6:8]))
    # add to model
    push!(
        active_part(model, state).line_geometry,
        NgonElement(color, Line(p1, p2))
    )
    return state
end

"""
    read_triangle!

For reading lines of type TRIANGLE
"""
function read_triangle!(model, state, line)
    @assert parse_command_code(line[1]) == TRIANGLE
    @assert length(line) == 11 "$line"
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64, line[3:5]))
    p2 = Point3D(parse.(Float64, line[6:8]))
    p3 = Point3D(parse.(Float64, line[9:11]))
    # add to model
    push!(
        active_part(model, state).triangle_geometry,
        NgonElement(color, Triangle(p1, p2, p3))
    )
    return state
end

"""
    read_quadrilateral!

For reading lines of type QUADRILATERAL
"""
function read_quadrilateral!(model, state, line)
    @assert parse_command_code(line[1]) == QUADRILATERAL
    # @assert length(line) == 14 "$line"
    @assert length(line) >= 14 "$line"
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64, line[3:5]))
    p2 = Point3D(parse.(Float64, line[6:8]))
    p3 = Point3D(parse.(Float64, line[9:11]))
    p4 = Point3D(parse.(Float64, line[12:14]))
    # add to model
    push!(
        active_part(model, state).quadrilateral_geometry,
        NgonElement(color, GeometryBasics.Quadrilateral(p1, p2, p3, p4))
    )
    return state
end

"""
    read_optional_line!

For reading lines of type OPTIONAL_LINE
"""
function read_optional_line!(model, state, line)
    @assert parse_command_code(line[1]) == OPTIONAL_LINE
    @assert length(line) == 14
    color = parse_color(line[2])
    p1 = Point3D(parse.(Float64, line[3:5]))
    p2 = Point3D(parse.(Float64, line[6:8]))
    p3 = Point3D(parse.(Float64, line[9:11]))
    p4 = Point3D(parse.(Float64, line[12:14]))
    # add to model
    push!(
        active_part(model, state).optional_line_geometry,
        OptionalLineElement(
            color,
            Line(p1, p2),
            Line(p3, p4)
        ))
    return state
end

"""
    populate_part_geometry!(model,frontier=Set(collect(part_keys(model))))

Load all geometry into `model.parts`. Loading is recursive, so that geometry
will be loaded through arbitrary levels of nested subparts until finally being
stored in each atomic part that is referenced by the main model(s).
"""
function populate_part_geometry!(model, frontier=Set(collect(part_keys(model))); ignore_rotation_determinant=false)
    explored = Set{String}()
    while !isempty(frontier)
        subcomponent = pop!(frontier)
        push!(explored, subcomponent)

        if has_model(model, subcomponent)
            continue
        end
        partfile = find_part_file(subcomponent)
        if isnothing(partfile)
            if subcomponent in all_part_keys(model)
                for k in all_part_keys(model)
                    if !(k in explored)
                        push!(frontier, k)
                    end
                end
                continue
            end
            error("Could not find part file for $subcomponent and it is not a submodel in the current model")
        end
        parse_ldraw_file!(model, partfile, MPDModelState(active_part=subcomponent);
            ignore_rotation_determinant=ignore_rotation_determinant
        )
        for k in all_part_keys(model)
            if !(k in explored)
                push!(frontier, k)
            end
        end
    end
    # go back through and recursively load geometry from subcomponents
    frontier = explored
    explored = Set{String}()
    while !isempty(frontier)
        name = pop!(frontier)
        part = get_part(model, name)
        recurse_part_geometry!(model, part, explored)
        setdiff!(frontier, explored)
    end
    model
end
function recurse_part_geometry!(model, part::DATModel, explored)
    if get_status(part.populated)
        push!(explored, part.name)
        return part
    end
    for ref in part.subfiles
        if has_part(model, ref.file)
            subpart = get_part(model, ref.file)
            if !(ref.file in explored)
                recurse_part_geometry!(model, subpart, explored)
            end
            incorporate_geometry!(part, ref, subpart)
        end
    end
    set_status!(part.populated, true)
    push!(explored, part.name)
    part
end

const LDRAW_BASE_FRAME = SMatrix{3,3,Float64}(
    1.0, 0.0, 0.0,
    0.0, 0.0, -1.0,
    0.0, 1.0, 0.0
)
"""
    ldraw_base_frame()

Returns a rotation matrix that defines the base LDraw coordinate system.
"""
ldraw_base_frame() = deepcopy(LDRAW_BASE_FRAME)
ldraw_base_transform() = Translation(0.0, 0.0, 0.0) ∘ LinearMap(ldraw_base_frame())

function (t::AffineMap)(g::G) where {G<:GeometryBasics.Ngon}
    G(map(t, g.points))
end
(t::AffineMap)(g::G) where {G<:NgonElement} = G(g.color, t(g.geom))
(t::AffineMap)(g::G) where {G<:OptionalLineElement} = G(g.color, t(g.geom), t(g.control_pts))
function Base.:(*)(r::Rotation, g::G) where {G<:GeometryBasics.Ngon}
    G(map(p -> r * p, g.points))
end
function Base.:(*)(g::G, x::Float64) where {G<:GeometryBasics.Ngon}
    G(map(p -> p * x, g.points))
end
Base.:(*)(g::G, x::Float64) where {G<:NgonElement} = G(g.color, g.geom * x)
Base.:(*)(g::G, x::Float64) where {G<:OptionalLineElement} = G(g.color, g.geom * x, g.control_pts * x)
function scale_translation(T::AffineMap, scale::Float64)
    compose(Translation(scale * T.translation...), LinearMap(T.linear))
end

"""
    change_coordinate_system!(model::MPDModel,T)

Transform the coordinate system of the entire model
"""
function change_coordinate_system!(model::MPDModel, T=ldraw_base_transform(), scale=1.0; ignore_rotation_determinant=false)
    Tinv = inv(T)
    for (k, m) in model.models
        for step in m.steps
            for i in 1:length(step.lines)
                ref = step.lines[i]
                t = build_transform(ref)
                new_t = scale_translation(T ∘ t ∘ Tinv, scale)
                step.lines[i] = SubFileRef(ref, new_t; ignore_rotation_determinant=ignore_rotation_determinant)
            end
        end
    end
    for k in collect(all_part_keys(model))
        part = get_part(model, k)
        new_part = DATModel(part, T, scale)
        set_part!(model, new_part, k)
    end
    return model
end

end
