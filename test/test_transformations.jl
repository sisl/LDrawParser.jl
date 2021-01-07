let
    P3 = Point3{Float64}
    # p = Translation(1.0,2.0,3.0)
    # r = zero(UnitQuaternion)
    # t = compose(p,LinearMap(r))
    x = P3(0.0,0.0,0.0)
    l = Line(zeros(P3),ones(P3))
    tr = Triangle(
        zeros(P3),
        ones(P3),
        0.5*ones(P3))
    q = GeometryBasics.Ngon{3,Float64,4,P3}(
        zeros(P3),
        ones(P3),
        -ones(P3),
        ones(P3).+P3(1,2,3))

    for t in [
            compose(Translation(0.0,0.0,0.0),LinearMap(zero(UnitQuaternion))),
            compose(Translation(1.0,2.0,3.0),LinearMap(zero(UnitQuaternion))),
            compose(Translation(1.0,2.0,3.0),LinearMap(RotZ(π/4))),
        ]
        for g in [l,tr,q]
            gt = t(g) # transform
            for (p,pt) in zip(g.points,gt.points)
                @test array_isapprox(t(p),pt)
            end
            n = LDrawParser.NgonElement(1,g)
            nt = t(n)
            for (p,pt) in zip(n.geom.points,nt.geom.points)
                @test array_isapprox(t(p),pt)
            end
        end
        n = LDrawParser.OptionalLineElement(1,l,l)
        nt = t(n)
        for (p,pt) in zip(n.geom.points,nt.geom.points)
            @test array_isapprox(t(p),pt)
        end
    end
end
