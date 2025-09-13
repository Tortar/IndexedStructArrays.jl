# Loosely based on data structures from https://github.com/orlp/slotmap

const EMPTY_SLOTS = Memory{UInt64}(undef, 0)

# This is an alternative to IndexedStructVectors
# It is consistently faster but has some downsides.
# There are a max of 2^NBITS-1 active elements allowed at a time
# by default NBITS=32 so around 4 billion.
# Deleting and pushing elements slowly leaks memory
# at a rate of 8 bytes per 2^(63-NBITS) pairs of delete and push.
mutable struct SlotMapStructVector{NBITS, C}
    # This stores the generation and index into components, 
    # or the next free slot if vacant.
    # The MSb of the slot is one if vacant and zero if occupied
    slots::Memory{UInt64}
    # Used length of slots.
    # This is zero before any element is deleted
    slots_len::Int
    # Top of the free linked list stored in vacant slots
    # This is zero if there are no free slots
    free_head::Int
    last_id::Int64
    const components::C
end

function SlotMapStructVector{NBITS}(components::NamedTuple) where {NBITS}
    allequal(length.(values(components))) || error("All components must have equal length")
    len = length(first(components))
    val_mask = (UInt64(1) << NBITS) - 1
    if len > val_mask
        error("SlotMapStructVector can store at most $(val_mask) elements but got $(len) elements.")
    end
    # Start with generation 0
    comps = merge((ID=collect(Int64(1):Int64(len)),), components)
    SlotMapStructVector{NBITS, typeof(comps)}(EMPTY_SLOTS, Int64(0), Int64(0), Int64(len), comps)
end
SlotMapStructVector(components::NamedTuple) = SlotMapStructVector{32}(components)

function val_mask(isv::SlotMapStructVector{NBITS}) where {NBITS}
    (UInt64(1) << NBITS) - 1
end

function gen_mask(isv::SlotMapStructVector)
    ~(UInt64(1) << 63) & ~val_mask(isv)
end

function assert_invariants(isv::SlotMapStructVector)
    @assert val_mask(isv) isa UInt64
    @assert ispow2(val_mask(isv) + 1)
    slots = getfield(isv, :slots)
    slots_len = getfield(isv, :slots_len)
    free_head = getfield(isv, :free_head)
    last_id = getfield(isv, :last_id)
    comp = getfield(isv, :components)
    @assert allequal(length.(values(comp)))
    ID = comp.ID
    len = length(ID)
    @assert len ≤ val_mask(isv)
    @assert allunique(ID)
    @assert !signbit(last_id)
    for (i, id) in enumerate(ID)
        if iszero(slots_len)
            @assert i == id
        else
            @assert !signbit(id)
            slot_idx = Int(id & val_mask(isv))
            @assert slot_idx ≤ slots_len
            @assert slots[slot_idx] === id & gen_mask(isv) | UInt64(i)
        end
        @assert id ∈ isv
    end
    if iszero(slots_len)
        @assert isempty(slots)
        @assert iszero(free_head)
        @assert iszero(last_id & gen_mask(isv))
    else
        @assert slots_len ≤ length(slots)
        @assert length(slots) ≤ val_mask(isv)
        n_free = 0
        n_dead = 0
        max_gen = UInt64(0)
        for (slot_idx, slot) in enumerate(view(slots, 1:slots_len))
            gen = slot & gen_mask(isv)
            max_gen = max(max_gen, gen)
            if signbit(slot%Int64)
                if gen === gen_mask(isv)
                    n_dead += 1
                    # canonical dead slot
                    @assert slot === ~UInt64(0)
                else
                    n_free += 1
                    @assert slot & val_mask(isv) ≤ slots_len
                end
            else
                i = slot & val_mask(isv)
                @assert ID[i]%UInt64 === gen | UInt64(slot_idx)
            end
        end
        @assert len + n_free + n_dead == slots_len
        @assert last_id & gen_mask(isv) ≤ max_gen
        @assert last_id & val_mask(isv) ≤ slots_len
        # Finally check the free list
        visited = zeros(Bool, slots_len)
        p = free_head
        n = 0
        while !iszero(p)
            @assert p ≤ slots_len
            @assert !visited[p]
            visited[p] = true
            n += 1
            slot = slots[p]
            @assert signbit(slot%Int64)
            p = slot & val_mask(isv)
            gen = slot & gen_mask(isv)
            @assert gen !== gen_mask(isv)
        end
        @assert n == n_free
    end
end

Base.getproperty(isv::SlotMapStructVector, name::Symbol) = getfield(isv, :components)[name]

lastkey(isv::SlotMapStructVector) = getfield(isv, :last_id)

@inline function id_guess_to_index(isv::SlotMapStructVector, id::Int64, lasti::Int)::Int
    if id ∉ isv
        throw(KeyError(id))
    end
    slots = getfield(isv, :slots)
    slots_len = getfield(isv, :slots_len)
    if iszero(slots_len)
        id%Int
    else
        (slots[id & val_mask(isv)] & val_mask(isv))%Int
    end
end

function delete_id_index!(isv::SlotMapStructVector, id::Int64, i::Int)
    comps, slots = getfield(isv, :components), getfield(isv, :slots)
    slots_len, ID = getfield(isv, :slots_len), getfield(comps, :ID)
    startlen = length(ID)
    slot_idx = (id & val_mask(isv))%Int
    if iszero(slots_len)
        # Slots have not been allocated yet
        slots = Memory{UInt64}(undef, startlen)
        # Start with generation 0
        slots .= UInt64(1):UInt64(startlen)
        setfield!(isv, :slots, slots)
        setfield!(isv, :slots_len, startlen)
    end
    @inbounds old_slot = slots[slot_idx]
    removei! = a -> remove!(a, i)
    unrolled_map(removei!, values(comps))
    # Update free linked list
    free_head = getfield(isv, :free_head)
    # Free head is zero if the free list is empty
    if old_slot < gen_mask(isv)
        # The slot has not been used too many times to cause a generation overflow.
        @inbounds slots[slot_idx] = UInt64(1)<<63 | old_slot & ~val_mask(isv) | free_head%UInt64
        setfield!(isv, :free_head, slot_idx)
    else
        # Avoid adding the slot back to the free list if it has been used too many times
        @inbounds slots[slot_idx] = ~UInt64(0)
    end
    if i ≤ length(ID)
        # adjust values in slots because the components have swapped
        @inbounds moved_pid = ID[i]
        moved_slot_idx = (moved_pid & val_mask(isv))%Int
        @inbounds slots[moved_slot_idx] = slots[moved_slot_idx] & ~val_mask(isv) | i
    end
    return isv
end

function Base.deleteat!(isv::SlotMapStructVector, i::Int)
    comps = getfield(isv, :components)
    ID = getfield(comps, :ID)
    delete_id_index!(isv, ID[i], i)
end

function Base.delete!(isv::SlotMapStructVector, id::Int)
    i = id_guess_to_index(isv, id, id)
    delete_id_index!(isv, id, i)
end

function Base.delete!(isv::SlotMapStructVector, a::IndexedView)
    id, lasti = getfield(a, :id), getfield(a, :lasti)
    i = id_guess_to_index(isv, id, lasti)
    delete_id_index!(isv, id, i)
end

function Base.push!(isv::SlotMapStructVector, t::NamedTuple)
    comps, slots = getfield(isv, :components), getfield(isv, :slots)
    slots_len, free_head = getfield(isv, :slots_len), getfield(isv, :free_head)
    fieldnames(typeof(comps))[2:end] !== keys(t) && error("Tuple fields do not match container fields")
    ID = getfield(comps, :ID)
    startlen = Int64(length(ID))
    if startlen ≥ val_mask(isv)
        error("SlotMapStructVector can store at most $(val_mask(isv)) elements.")
    end
    if iszero(slots_len)
        push!(ID, startlen + 1)
        setfield!(isv, :last_id, startlen + 1)
    else
        if iszero(free_head)
            # push a slot to the end of slots
            old_slots_capacity = length(slots)
            if old_slots_capacity ≤ slots_len
                if old_slots_capacity ≥ val_mask(isv)
                    error("SlotMapStructVector is out of capacity")
                end
                # reallocate the slots
                # avoid having a capacity larger than val_mask(isv)
                new_slots_capacity = clamp(
                    overallocation(old_slots_capacity),
                    old_slots_capacity+1,
                    val_mask(isv)
                )
                new_slots = typeof(slots)(undef, Int(new_slots_capacity))
                copyto!(new_slots, slots)
                setfield!(isv, :slots, new_slots)
                slots = new_slots
            end
            # Start with generation 0
            setfield!(isv, :slots_len, slots_len + 1)
            new_id = Int64(slots_len) + 1
            push!(ID, new_id)
            setfield!(isv, :last_id, new_id)
            slots[new_id] = (startlen + 1)%UInt64
        else
            # Pick a slot off the free list
            @inbounds free_slot = slots[free_head]
            next_free_head = (free_slot & val_mask(isv))%Int
            old_gen = free_slot & gen_mask(isv)
            next_gen = old_gen + (val_mask(isv) + 1)
            new_slot = next_gen | UInt64(startlen + 1)
            new_id = (next_gen | free_head%UInt64)%Int64
            setfield!(isv, :free_head, next_free_head)
            @inbounds slots[free_head] = new_slot
            push!(ID, new_id)
            setfield!(isv, :last_id, new_id)
        end
    end
    unrolled_map(push!, values(comps)[2:end], t)
    return isv
end

function Base.show(io::IO, ::MIME"text/plain", x::SlotMapStructVector{N, C}) where {N, C}
    comps = getfield(x, :components)
    sC = string(C)[13:end]
    print("SlotMapStructVector{$sC")
    return display(comps)
end

function Base.keys(isv::SlotMapStructVector)
    return Keys(getfield(getfield(isv, :components), :ID))
end

@inline function Base.getindex(isv::SlotMapStructVector, id::Int64)
    return IndexedView(id, id_guess_to_index(isv, id, id), isv)
end

function Base.in(a::IndexedView, isv::SlotMapStructVector)
    getfield(a, :id) ∈ isv
end
function Base.in(id::Int64, isv::SlotMapStructVector)::Bool
    comps = getfield(isv, :components)
    slots_len, ID = getfield(isv, :slots_len), getfield(comps, :ID)
    iszero(slots_len) && return id ∈ eachindex(ID)
    if signbit(id)
        return false
    end
    slots = getfield(isv, :slots)
    slots_len = getfield(isv, :slots_len)
    slot_idx = id & val_mask(isv)
    if slot_idx ∉ 1:slots_len
        return false
    end
    @inbounds slot = slots[slot_idx]
    if slot & ~val_mask(isv) !== id & ~val_mask(isv)
        return false
    end
    true
end

# Copied from base/array.jl because this is not a public function
# https://github.com/JuliaLang/julia/blob/v1.11.6/base/array.jl#L1042-L1056

# Pick new memory size for efficiently growing an array
# TODO: This should know about the size of our GC pools
# Specifically we are wasting ~10% of memory for small arrays
# by not picking memory sizes that max out a GC pool
function overallocation(maxsize)
    maxsize < 8 && return 8;
    # compute maxsize = maxsize + 4*maxsize^(7/8) + maxsize/8
    # for small n, we grow faster than O(n)
    # for large n, we grow at O(n/8)
    # and as we reach O(memory) for memory>>1MB,
    # this means we end by adding about 10% of memory each time
    exp2 = sizeof(maxsize) * 8 - Core.Intrinsics.ctlz_int(maxsize)
    maxsize += (1 << div(exp2 * 7, 8)) * 4 + div(maxsize, 8)
    return maxsize
end
