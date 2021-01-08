let
    k = "43710.dat"
    model = parse_ldraw_file(find_part_file(k))
    explored = Set{String}()
    frontier = Set(collect(keys(model.parts)))
    while !isempty(frontier)
        subcomponent = pop!(frontier)
        push!(explored,subcomponent)
        partfile = find_part_file(subcomponent)
        if partfile === nothing
            @warn "Can't find file $subcomponent. Skipping..."
            continue
        end
        parse_ldraw_file!(model,find_part_file(subcomponent),
            LDrawParser.MPDModelState(
                active_model="",
                active_part=subcomponent
            )
        )
        for k in keys(model.parts)
            if !(k in explored)
                push!(frontier,k)
            end
        end
    end
    # for subcomponent in keys(model.parts) # updates on the fly
    #     @show subcomponent
    #     parse_ldraw_file!(model,find_part_file(subcomponent),
    #         LDrawParser.MPDModelState(
    #             active_model="",
    #             active_part=subcomponent
    #         )
    #     )
    # end
    model

    m = parse_ldraw_file(find_part_file("stud.dat"))


    parse_ldraw_file!(m,find_part_file("4-4disc.dat"),
        LDrawParser.MPDModelState(
            active_model="",
            active_part="4-4disc.dat"
        )
    )


end
