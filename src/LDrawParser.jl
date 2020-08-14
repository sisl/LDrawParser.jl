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

Encodes the raw geometry of a LDraw part stored in a .dat file
"""
struct DATModel
    name::String
    line_geometry::Vector{NgonElement{Line}}
    triangle_geometry::Vector{NgonElement{Triangle}}
    quadrilateral_geometry::Vector{NgonElement{GeometryBasics.NNgon{4}}}
    optional_line_geometry::Vector{OptionalLineElement}
    subfiles::Vector{SubFileRef} # points to other DATModels
    DATModel() = new(
        "",
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
"""
struct MPDModel
    # sub_file_refs::Vector{SubFileRef}
    # ldr_models::Vector{DATModel}
    models::Dict{String,SubModelPlan} # each file is a list of steps
    parts::Dict{String,DATModel}
    # steps
    MPDModel() = new(
        Vector{SubFileRef}(),
        Vector{DATModel}([DATModel()]),
        Vector{SubModelPlan}()
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
function active_building_step(model::MPDModel,state)
    active_submodel = active_submodel(model,state)
    return active_building_step(active_submodel,state)
end

"""
    parse_ldraw_file!

Args:
    - model
    - filename or IO
"""
function parse_ldraw_file!(model,io)
    state = MPDModelState()
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
function parse_ldraw_file!(model,filename::String)
    open(filename,"r") do io
        parse_ldraw_file!(model,io)
    end
end

parse_ldraw_file(io) = parse_ldraw_file!(MPDModel(),io)
parse_color(c) = parse(Int,c)

"""
    read_meta_line(model,line)
"""
function read_meta_line!(model,state,line)
    @assert parse(Int,line[1]) == META
    cmd = line[2]
    if cmd == "FILE"
        file_name = join(line[3:end]," ")
        ext = splitext(file_name)[2]
        if ext == ".dat"
            push!(model.models,)
        elseif ext == ".mpd" || ext == ".ldr"
            push!(model.models,SubModelPlan(file_name))
            state = MPDModelState(state,active_model = file_name)
        end
    end
    # TODO
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
    push!(model.sub_file_refs,ref)
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
        active_building_step(model).line_geometry,
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
        active_building_step(model).triangle_geometry,
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
        active_building_step(model).quadrilateral_geometry,
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
        active_building_step(model).optional_line_geometry,
        OptionalLineElement(
            color,
            Line(p1,p2),
            Line(p3,p4)
        ))
    return state
end


end
