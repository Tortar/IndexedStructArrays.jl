module IndexedStructVectors

using Unrolled

export IndexedStructVector, SlotMapStructVector, getfields, id, isvalid

function remove!(a, i)
    @inbounds a[i], a[end] = a[end], a[i]
    pop!(a)
    return
end

struct Keys
    ID::Vector{Int64}
end
Base.iterate(k::Keys) = Base.iterate(k.ID)
Base.iterate(k::Keys, state) = Base.iterate(k.ID, state)
Base.IteratorSize(::Keys) = Base.HasLength()
Base.length(k::Keys) = length(k.ID)
Base.eltype(::Keys)= Int64

struct IndexedView{S}
    id::Int64
    lasti::Int
    isv::S
end

id(a::IndexedView) = getfield(a, :id)

isvalid(a::IndexedView) = a in getfield(a, :isv)

@inline function Base.getproperty(a::IndexedView, name::Symbol)
    id, isv = getfield(a, :id), getfield(a, :isv)
    comps = getfield(isv, :components)
    f = getfield(comps, name)
    lasti = getfield(a, :lasti)
    i = id_guess_to_index(isv, id, lasti)
    @inbounds f[i]
end

@inline function Base.setproperty!(a::IndexedView, name::Symbol, x)
    id, isv = getfield(a, :id), getfield(a, :isv)
    comps = getfield(isv, :components)
    f = getfield(comps, name)
    lasti = getfield(a, :lasti)
    i = id_guess_to_index(isv, id, lasti)
    return (@inbounds f[i] = x)
end

@inline function getfields(a::IndexedView)
    id, isv = getfield(a, :id), getfield(a, :isv)
    comps = getfield(isv, :components)
    lasti = getfield(a, :lasti)
    i = id_guess_to_index(isv, id, lasti)
    getindexi = ar -> @inbounds ar[i]
    vals = unrolled_map(getindexi, values(comps)[2:end])
    names = fieldnames(typeof(comps))[2:end]
    return NamedTuple{names}(vals)
end

function Base.show(io::IO, ::MIME"text/plain", x::IndexedView)
    !isvalid(x) && return print(io, "InvalidIndexView(ID = $(getfield(x, :id)))")
    id, isv = getfield(x, :id), getfield(x, :isv)
    comps = getfield(isv, :components)
    lasti = getfield(x, :lasti)
    i = id_guess_to_index(isv, id, lasti)
    fields = NamedTuple(y => getfield(comps, y)[i] for y in fieldnames(typeof(comps)))
    return print(io, "IndexedView$fields")
end

include("dict.jl")
include("slotmap.jl")

end
