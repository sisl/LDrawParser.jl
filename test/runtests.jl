using LDrawParser
using CoordinateTransformations
using Rotations
using GeometryBasics

using Test
using Logging

# Set logging level
log_level = Logging.Warn # Logging.Debug, Logging.Info, Logging.Warn, Logging.Error
global_logger(SimpleLogger(stderr, log_level))

@inline function array_isapprox(x::AbstractArray{F},
                  y::AbstractArray{F};
                  rtol::F=sqrt(eps(F)),
                  atol::F=zero(F)) where {F<:AbstractFloat}

    # Easy check on matching size
    if length(x) != length(y)
        return false
    end

    for (a,b) in zip(x,y)
        if !isapprox(a,b, rtol=rtol, atol=atol)
            return false
        end
    end
    return true
end

# Check if array equals a single value
@inline function array_isapprox(x::AbstractArray{F},
                  y::F;
                  rtol::F=sqrt(eps(F)),
                  atol::F=zero(F)) where {F<:AbstractFloat}

    for a in x
        if !isapprox(a, y, rtol=rtol, atol=atol)
            return false
        end
    end
    return true
end

# Define package tests
@time @testset "LDrawParser Package Tests" begin
    testdir = joinpath(dirname(@__DIR__), "test")
    @time @testset "LDrawParser.Transformations" begin
        include(joinpath(testdir, "test_transformations.jl"))
    end
    @time @testset "LDrawParser.Loading" begin
        include(joinpath(testdir, "test_loading.jl"))
    end
end
