let
    k = "43710.dat"
    model = parse_ldraw_file(find_part_file(k))
    for subcomponent in keys(model.parts)
        parse_ldraw_file!(model,find_part_file(subcomponent),
            # LDrawParser.MPDModelState(
            #     active_model="",
            #     active_part=subcomponent
            # )
        )
    end
    model

    m = parse_ldraw_file(find_part_file("stud.dat"))


    parse_ldraw_file!(m,find_part_file("4-4disc.dat"),
        LDrawParser.MPDModelState(
            active_model="",
            active_part="4-4disc.dat"
        )
    )


end
