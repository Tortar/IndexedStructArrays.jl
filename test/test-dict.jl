
using IndexedStructVectors
using Test

@testset "IndexedStructVector" begin
    @testset "construction" begin
        s = IndexedStructVector((x = [10, 20, 30], y = ["a", "b", "c"]))
        @test length(collect(keys(s))) == 3
        @test IndexedStructVectors.lastkey(s) == 3
        @test_throws ErrorException IndexedStructVector((x = [1,2], y = ["a"]))
    end

    @testset "getindex/getproperty/setproperty!/getfields" begin
        s = IndexedStructVector((num = [1,2,3], name = ["x","y","z"]))
        a = s[2]

        @test typeof(a) <: IndexedStructVectors.IndexedRefView
        @test a.num == 2
        @test a.name == "y"

        a.num = 42
        @test s[2].num == a.num == 42

        nt = getfields(s[2])
        @test nt.num == 42
        @test nt.name == "y"
        @test length(nt) == 2
    end

    @testset "deleteat!/delete!/push!" begin
        s = IndexedStructVector((num = [10,20,30,40], tag = ['a','b','c','d']))

        ids_before = collect(keys(s))
        @test ids_before == [1,2,3,4]

        deleteat!(s, 2)
        ids_after = collect(keys(s))
        @test length(ids_after) == 3
        @test (2 in ids_after) == false
        @test 1 ∈ ids_after

        push!(s, (num = 111, tag = 'z'))
        new_id = IndexedStructVectors.lastkey(s)
        @test new_id == id(s[new_id]) == 5
        @test new_id in collect(keys(s))
        @test s[new_id].num == 111

        delete!(s, 4)
        ids_after = collect(keys(s))
        @test (4 in ids_after) == false
        @test getfield(s, :id)[2] == 5
        @test s[getfield(s, :id)[2]].num == 111
        @test length(ids_after) == 3

        @test_throws KeyError delete!(s, 9999)
    end
end
