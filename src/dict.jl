
mutable struct IndexedStructVector{S}
    del::Bool
    nextlastid::Int64
    const index::Vector{Base.RefValue{Int}}
    const id::Vector{Int}
    const id_to_index::Dict{Int64, Int}
    const components::S
    function IndexedStructVector(comps::NamedTuple)
        allequal(length.(values(comps))) || error("All components must have equal length")
        len = length(first(comps))
        return new{typeof(comps)}(false, len, Ref.(collect(1:len)), collect(1:len), Dict{Int64,Int}(), comps)
    end
end

Base.getproperty(isv::IndexedStructVector, name::Symbol) = getfield(isv, :components)[name]

lastkey(isv::IndexedStructVector) = getfield(isv, :nextlastid)

@inline function id_guess_to_index(isv::IndexedStructVector, id::Int64, lasti::Int)::Int
    del = getfield(isv, :del)
    comps = getfield(isv, :components)
    ID = getfield(isv, :id)
    if !del
        checkbounds(Bool, ID, id) || throw(KeyError(id))
        id
    else
        if lasti ∈ eachindex(ID) && (@inbounds ID[lasti] == id)
            lasti
        else
            getfield(isv, :id_to_index)[id]
        end
    end
end

@inline function delete_id_index!(isv::IndexedStructVector, id::Int64, i::Int)
    comps, id_to_index = getfield(isv, :components), getfield(isv, :id_to_index)
    del, ID, index = getfield(isv, :del), getfield(isv, :id), getfield(isv, :index)
    !del && setfield!(isv, :del, true)
    removei! = a -> remove!(a, i)
    unrolled_map(removei!, values(comps))
    remove!(ID, i)
    index[i][] = 0
    remove!(index, i)
    delete!(id_to_index, id)
    if i <= length(ID)
        index[i][] = i
        id_to_index[(@inbounds ID[i])] = i
    end
    return isv
end

function Base.deleteat!(isv::IndexedStructVector, i::Int)
    comps = getfield(isv, :components)
    ID = getfield(isv, :id)
    delete_id_index!(isv, ID[i], i)
end

function Base.delete!(isv::IndexedStructVector, id::Int)
    i = id_guess_to_index(isv, id, id)
    delete_id_index!(isv, id, i)
end

function Base.delete!(isv::IndexedStructVector, a::IndexedRefView)
    lasti = getfield(a, :lasti)[]
    id = getfield(isv, :id)[lasti]
    delete_id_index!(isv, id, i)
end

function Base.push!(isv::IndexedStructVector, t::NamedTuple)
    comps, id_to_index = getfield(isv, :components), getfield(isv, :id_to_index)
    fieldnames(typeof(comps)) != keys(t) && error("Tuple fields do not match container fields")
    ID, index, lastid = getfield(isv, :id), getfield(isv, :index), getfield(isv, :nextlastid)
    nextlastid = setfield!(isv, :nextlastid, lastid + 1)
    push!(ID, nextlastid)
    push!(index, Ref(length(ID)))
    unrolled_map(push!, values(comps), t)
    getfield(isv, :del) && (id_to_index[nextlastid] = length(ID))
    return isv
end

function Base.show(io::IO, ::MIME"text/plain", x::IndexedStructVector{C}) where C
    comps = getfield(x, :components)
    sC = string(C)[13:end]
    print("IndexedStructVector{$sC")
    return display(comps)
end

function Base.keys(isv::IndexedStructVector)
    return Keys(getfield(isv, :id))
end

@inline function Base.getindex(isv::IndexedStructVector, id::Int)
    index = getfield(isv, :index)
    return IndexedRefView(index[id_guess_to_index(isv, id, id)], isv)
end

function Base.in(a::IndexedRefView, isv::IndexedStructVector)
    return getfield(a, :lasti)[] != 0
end
function Base.in(id::Int64, isv::IndexedStructVector)
    comps = getfield(isv, :components)
    del, ID = getfield(isv, :del), getfield(isv, :id)
    !del && return 1 <= id <= length(ID)
    id ∈ eachindex(ID) && (@inbounds ID[id] == id) && return true
    id_to_index = getfield(isv, :id_to_index)
    return id in keys(id_to_index)
end
