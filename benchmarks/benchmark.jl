#!/usr/bin/env -S OPENBLAS_NUM_THREADS=1 JULIA_LOAD_PATH=@ julia --project=@script --threads=1 --startup-file=no

using Chairmarks
using IndexedStructVectors
using Random
using Statistics

"""
    Setup a `size` length vector
    after `size*fract_shuffled` random delete and push pairs
"""
function setup_isv(type, size, fract_shuffled)
    isv = type((;num=ones(size)))
    n_del_push = round(Int, size*fract_shuffled)
    for i in 1:n_del_push
        id = rand(isv.ID)
        delete!(isv, id)
        push!(isv, (;num=rand()))
    end
    isv
end

function bench_rand_access(type, size, fract_shuffled)
    isv = setup_isv(type, size, fract_shuffled)
    ids = shuffle(isv.ID)
    @be(isv[rand(ids)].num, seconds=2)
end

function bench_rand_in(type, size, fract_shuffled)
    isv = setup_isv(type, size, fract_shuffled)
    @be(rand(Int64) ∈ isv, seconds=2)
end

function bench_rand_deletes(type, size, fract_shuffled, n_deletes)
    @be(
        let
            isv = setup_isv(type, size, fract_shuffled)
            ids = shuffle(isv.ID)
            (isv, ids)
        end,
        (x)->let
            for i in 1:n_deletes
                delete!(x[1], x[2][i])
            end
        end,
        evals=1,
        seconds=2,
    )
end

function bench_pushes(type, size, fract_shuffled, n_pushes)
    @be(
        setup_isv(type, size, fract_shuffled),
        (x)->let
            for i in 1:n_pushes
                push!(x, (;num=3.14))
            end
        end,
        evals=1,
        seconds=2,
    )
end

using CairoMakie

function save_benchmark_plots(;
        outdir= pwd(),
        ntrials= 5,
    )
    datatypes = [
        IndexedStructVector,
        SlotMapStructVector,
    ]
    # Test parameters
    sizes = Int[1E4, 1E5, 1E6, 1E7]
    fract_shuffled_values = [0.0, 2.0]

    fig = Figure(size = (1200, 800))

    ax = Axis(fig[1, 1], 
        title = "Random getindex Performance",
        xlabel = "Vector Size", 
        ylabel = "Time (ns)",
        xscale = log10,
        limits = ((nothing,nothing), (0.0,nothing)),
    )
    @info ax.title[]
    out = Dict()
    for trial in 1:ntrials
        for (i, dtype) in enumerate(datatypes)
            for fract_shuffled in fract_shuffled_values
                test_name = "$(dtype) $(fract_shuffled*100)% shuffled"
                positions = get!(out, test_name, [])
                for size in sizes
                    result = mean(bench_rand_access(dtype, size, fract_shuffled))
                    push!(positions, (size, result.time*1E9))
                end
            end
        end
    end
    for (test_name, positions) in sort(pairs(out))
        scatter!(ax, positions; label= test_name, marker= :cross)
    end

    ax = Axis(fig[1, 2], 
        title = "Random in Performance",
        xlabel = "Vector Size", 
        ylabel = "Time (ns)",
        xscale = log10,
        limits = ((nothing,nothing), (0.0,nothing)),
    )
    @info ax.title[]
    out = Dict()
    for trial in 1:ntrials
        for (i, dtype) in enumerate(datatypes)
            for fract_shuffled in fract_shuffled_values
                test_name = "$(dtype) $(fract_shuffled*100)% shuffled"
                positions = get!(out, test_name, [])
                for size in sizes
                    result = mean(bench_rand_in(dtype, size, fract_shuffled))
                    push!(positions, (size, result.time*1E9))
                end
            end
        end
    end
    for (test_name, positions) in sort(pairs(out))
        scatter!(ax, positions; label= test_name, marker= :cross)
    end

    ax = Axis(fig[2, 1], 
        title = "Delete Performance",
        xlabel = "Vector Size", 
        ylabel = "Time per delete (ns)",
        xscale = log10,
        limits = ((nothing,nothing), (0.0,nothing)),
    )
    @info ax.title[]
    out = Dict()
    for trial in 1:ntrials
        for (i, dtype) in enumerate(datatypes)
            for fract_shuffled in fract_shuffled_values
                test_name = "$(dtype) $(fract_shuffled*100)% shuffled"
                positions = get!(out, test_name, [])
                for size in sizes
                    result = mean(bench_rand_deletes(dtype, size, fract_shuffled, size))
                    push!(positions, (size, result.time*1E9/size))
                end
            end
        end
    end
    for (test_name, positions) in sort(pairs(out))
        scatter!(ax, positions; label= test_name, marker= :cross)
    end

    ax = Axis(fig[2, 2], 
        title = "Push Performance",
        xlabel = "Vector Size", 
        ylabel = "Time per push (ns)",
        xscale = log10,
        limits = ((nothing,nothing), (0.0,nothing)),
    )
    @info ax.title[]
    out = Dict()
    for trial in 1:ntrials
        for (i, dtype) in enumerate(datatypes)
            for fract_shuffled in fract_shuffled_values
                test_name = "$(dtype) $(fract_shuffled*100)% shuffled"
                positions = get!(out, test_name, [])
                for size in sizes
                    result = mean(bench_pushes(dtype, 100, fract_shuffled, size))
                    push!(positions, (size, result.time*1E9/size))
                end
            end
        end
    end
    for (test_name, positions) in sort(pairs(out))
        scatter!(ax, positions; label= test_name, marker= :cross)
    end
    Legend(fig[1,3], ax)

    # # Save the plot
    outpath = joinpath(outdir, "benchmark.png")
    save(outpath, fig)
    println("Benchmark plots saved to $(repr(outpath))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    save_benchmark_plots()
end
