module LDrawParser

using LightGraphs
using GeometryBasics
using Parameters

# Each line of an LDraw file begins with a number 0-5
const META          = 0
const SUB_FILE_REF  = 1
const LINE          = 2
const TRIANGLE      = 3
const QUADRILATERAL = 4
const OPTIONAL      = 5

function parse_line(line)
    split_line = split(line," ")
    return
end

const Point3D   = Point

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
    line::Line
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

export
    MPDModel,
    parse_ldraw_file!,
    parse_ldraw_file

"""
    DATModel

Encodes the raw geometry of a LDraw part stored in a .dat file. It is possible
to avoid populating the geometry fields, which is useful for large models or
models that use parts from the LDraw library.
"""
struct DATModel
    name::String
    line_geometry::Vector{NgonElement{Line}}
    triangle_geometry::Vector{NgonElement{Triangle}}
    quadrilateral_geometry::Vector{NgonElement{GeometryBasics.NNgon{4}}}
    optional_line_geometry::Vector{OptionalLineElement}
    subfiles::Vector{SubFileRef} # points to other DATModels
    DATModel(name::String) = new(
        name,
        Vector{NgonElement{Line}}(),
        Vector{NgonElement{Triangle}}(),
        Vector{NgonElement{GeometryBasics.NNgon{4}}}(),
        Vector{OptionalLineElement}(),
        Vector{String}()
    )
end

# """
#     LDRModel
#
# Encodes the LDraw information stored in a LDR file.
# """
# struct LDRModel
#     id
#     name
#     steps::Vector{BuildingStep}
#     parts::Vector{DATModel}
# end


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

@with_kw struct MPDModelState
    active_model::String = ""
    active_part::String = ""
end
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
    @assert !haskey(model.parts,name)
    model.parts[name] = DATModel(name)
    return MPDModelState(state,active_part=name)
end
function add_sub_file_placement!(model::MPDModel,state,ref)
    push!(active_building_step(model,state),ref)
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
        @show line
        if length(line) == 0
            continue
        end
        split_line = split(line," ")
        code = parse(Int,split_line[1])
        if code == META
            state = read_meta_line!(model,state,split_line)
        elseif code == SUB_FILE_REF
            state = read_sub_file_ref!(model,state,split_line)
        elseif code == LINE
            state = read_line!(model,state,split_line)
        elseif code == TRIANGLE
            state = read_triangle!(model,state,split_line)
        elseif code == QUADRILATERAL
            state = read_quadrilateral!(model,state,split_line)
        elseif code == OPTIONAL
            state = read_optional_line!(model,state,split_line)
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
    @assert parse(Int,line[1]) == META
    cmd = line[2]
    if cmd == "FILE"
        filename = join(line[3:end]," ")
        ext = splitext(filename)[2]
        if ext == ".dat"
            state = set_new_active_part!(model,state,filename)
        elseif ext == ".mpd" || ext == ".ldr"
            state = set_new_active_model!(model,state,filename)
        end
    elseif cmd == "STEP"
        set_new_active_building_step!(model,state)
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
    @assert parse(Int,line[1]) == SUB_FILE_REF
    @assert length(line) >= 15
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
    read_line

For reading lines of type LINE
"""
function read_line(model,state,line)
    @assert parse(Int,line[1]) == LINE
    @assert length(line) == 8
    color = parse_color(line[2])
    p1 = Point3D(parse.(Int,line[3:5]))
    p2 = Point3D(parse.(Int,line[6:8]))
    # add to model
    push!(
        active_part(model).line_geometry,
        NgonElement(color,Line(p1,p2))
        )
    return state
end

"""
    read_triangle

For reading lines of type TRIANGLE
"""
function read_triangle(model,state,triangle)
    @assert parse(Int,line[1]) == TRIANGLE
    @assert length(line) == 11
    color = parse_color(line[2])
    p1 = Point3D(parse.(Int,line[3:5]))
    p2 = Point3D(parse.(Int,line[6:8]))
    p3 = Point3D(parse.(Int,line[9:11]))
    # add to model
    push!(
        active_part(model).triangle_geometry,
        NgonElement(color,Triangle(p1,p2,p3))
        )
    return state
end

"""
    read_quadrilateral

For reading lines of type QUADRILATERAL
"""
function read_quadrilateral(model,state,line)
    @assert parse(Int,line[1]) == QUADRILATERAL
    @assert length(line) == 14
    color = parse_color(line[2])
    p1 = Point3D(parse.(Int,line[3:5]))
    p2 = Point3D(parse.(Int,line[6:8]))
    p3 = Point3D(parse.(Int,line[9:11]))
    p4 = Point3D(parse.(Int,line[12:14]))
    # add to model
    push!(
        active_part(model).quadrilateral_geometry,
        NgonElement(color,GeometryBasics.NNgon{4}(p1,p2,p3,p4))
        )
    return state
end

"""
    read_quadrilateral

For reading lines of type QUADRILATERAL
"""
function read_optional_line(model,state,line)
    @assert parse(Int,line[1]) == OPTIONAL_LINE
    @assert length(line) == 14
    color = parse_color(line[2])
    p1 = Point3D(parse.(Int,line[3:5]))
    p2 = Point3D(parse.(Int,line[6:8]))
    p3 = Point3D(parse.(Int,line[9:11]))
    p4 = Point3D(parse.(Int,line[12:14]))
    # add to model
    push!(
        active_part(model).optional_line_geometry,
        OptionalLineElement(
            color,
            Line(p1,p2),
            Line(p3,p4)
        ))
    return state
end


end
