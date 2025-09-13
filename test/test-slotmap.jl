
using IndexedStructVectors
using IndexedStructVectors: assert_invariants
using Test

@testset "SlotMapStructVector" begin
    @testset "construction" begin
        s = SlotMapStructVector((x = [10, 20, 30], y = ["a", "b", "c"]))
        assert_invariants(s)
        @test length(collect(keys(s))) == 3
        @test IndexedStructVectors.lastkey(s) == 3
        @test_throws ErrorException SlotMapStructVector((x = [1,2], y = ["a"]))
    end

    @testset "getindex/getproperty/setproperty!/getfields" begin
        s = SlotMapStructVector((num = [1,2,3], name = ["x","y","z"]))
        assert_invariants(s)
        a = s[2]

        @test typeof(a) <: IndexedStructVectors.IndexedView
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
        s = SlotMapStructVector((num = [10,20,30,40], tag = ['a','b','c','d']))
        assert_invariants(s)

        ids_before = collect(keys(s))
        @test ids_before == [1,2,3,4]

        deleteat!(s, 2)
        assert_invariants(s)
        ids_after = collect(keys(s))
        @test length(ids_after) == 3
        @test (2 in ids_after) == false
        @test 1 ∈ ids_after

        push!(s, (num = 111, tag = 'z'))
        assert_invariants(s)
        new_id = IndexedStructVectors.lastkey(s)
        @test new_id == s[new_id].ID == id(s[new_id]) == 1<<32 | 2
        @test new_id in collect(keys(s))
        @test s[new_id].num == 111

        delete!(s, 4)
        assert_invariants(s)
        ids_after = collect(keys(s))
        @test (4 in ids_after) == false
        @test s.ID[2] == new_id
        @test s[new_id].num == 111
        @test length(ids_after) == 3
        @test 4 ∉ s
        @test -4 ∉ s
        @test_throws KeyError s[4]
        @test_throws KeyError s[-4]

        @test_throws KeyError delete!(s, 9999)

        # pushing initially empty
        s = SlotMapStructVector((num = Int[], tag = Char[]))
        ids = Int64[]
        assert_invariants(s)
        for i in 1:100
            push!(s, (num = i, tag = Char(i)))
            push!(ids, IndexedStructVectors.lastkey(s))
            assert_invariants(s)
        end
        delete!(s, pop!(ids))
        for i in 101:1000
            push!(s, (num = i, tag = Char(i)))
            push!(ids, IndexedStructVectors.lastkey(s))
            assert_invariants(s)
        end
        while !isempty(ids)
            delete!(s, pop!(ids))
            assert_invariants(s)
        end
        for i in 1:100
            push!(s, (num = i, tag = Char(i)))
            push!(ids, IndexedStructVectors.lastkey(s))
            assert_invariants(s)
        end
    end

    @testset "test logic for dead slots" begin
        # if NBITS=2 capacity is limited to 3 elements
        @test_throws ErrorException SlotMapStructVector{2}((;num = [10,20,30,40]))
        s = SlotMapStructVector{2}((;num = [10,20,30]))
        @test_throws ErrorException push!(s, (; num=10))
        s = SlotMapStructVector{2}((;num = [10,20,30]))
        deleteat!(s, 3)
        assert_invariants(s)
        push!(s, (; num=10))
        assert_invariants(s)
        deleteat!(s, 3)
        push!(s, (; num=10))
        assert_invariants(s)
        @test_throws ErrorException push!(s, (; num=10))

        # Now simulate pushing and deleting 2^61 times so one of the slots becomes dead
        deleteat!(s, 3)
        getfield(s, :slots)[3] = ~UInt64(0)
        setfield!(s, :free_head, 0)
        @test_throws ErrorException push!(s, (; num=10))

        s = SlotMapStructVector{61}((;num = [10,20,30,40]))
        # As the last id is deleted and pushed repeatedly, it should get the following
        # ids.
        expected_last_ids = [
            0<<61 | Int64(4),
            1<<61 | Int64(4),
            2<<61 | Int64(4),
            3<<61 | Int64(4),
            0<<61 | Int64(5),
            1<<61 | Int64(5),
            2<<61 | Int64(5),
            3<<61 | Int64(5),
            0<<61 | Int64(6),
        ]
        for expected_last_id in expected_last_ids
            @test s.ID == [1,2,3, expected_last_id]
            delete!(s, expected_last_id)
            assert_invariants(s)
            @test s.ID == [1,2,3]
            push!(s, (;num = 50))
            assert_invariants(s)
        end

        s = SlotMapStructVector{61}((;num = [10,20,30,40]))
        delete!(s, Int64(1))
        # As the first id is deleted and pushed repeatedly, it should get the following
        # ids.
        expected_last_ids = [
            1<<61 | Int64(1),
            2<<61 | Int64(1),
            3<<61 | Int64(1),
            0<<61 | Int64(5),
            1<<61 | Int64(5),
            2<<61 | Int64(5),
            3<<61 | Int64(5),
            0<<61 | Int64(6),
        ]
        for expected_last_id in expected_last_ids
            assert_invariants(s)
            push!(s, (;num = 50))
            assert_invariants(s)
            @test s.ID == [4,2,3, expected_last_id]
            delete!(s, expected_last_id)
            assert_invariants(s)
            @test s.ID == [4,2,3]
        end
    end
end
