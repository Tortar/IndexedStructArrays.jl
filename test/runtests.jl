
using IndexedStructVectors
using Aqua, Test

@testset "IndexedStructVectors.jl" begin

    if "CI" in keys(ENV)
        @testset "Code quality (Aqua.jl)" begin
            Aqua.test_all(IndexedStructVectors, deps_compat=false)
            Aqua.test_deps_compat(IndexedStructVectors, check_extras=false)
        end
    end

    include("test-dict.jl")
    include("test-slotmap.jl")
end
