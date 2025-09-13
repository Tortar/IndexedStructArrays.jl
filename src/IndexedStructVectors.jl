module IndexedStructVectors

using Unrolled

export IndexedStructVector, getfields, id, isvalid

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

struct IndexedRefView{S}
    lasti::Base.RefValue{Int}
    isv::S
end


id(a::IndexedRefView) = getfield(getfield(a, :isv), :id)[getfield(a, :lasti)[]]

isvalid(a::IndexedRefView) = a in getfield(a, :isv)

@inline function Base.getproperty(a::IndexedRefView, name::Symbol)
    isv = getfield(a, :isv)
    comps = getfield(isv, :components)
    f = getfield(comps, name)
    lasti = getfield(a, :lasti)[]
    @inbounds f[lasti]
end

@inline function Base.setproperty!(a::IndexedRefView, name::Symbol, x)
    isv = getfield(a, :isv)
    comps = getfield(isv, :components)
    f = getfield(comps, name)
    lasti = getfield(a, :lasti)[]
    return (@inbounds f[lasti] = x)
end

@inline function getfields(a::IndexedRefView)
    isv = getfield(a, :isv)
    comps = getfield(isv, :components)
    i = getfield(a, :lasti)[]
    getindexi = ar -> @inbounds ar[i]
    vals = unrolled_map(getindexi, values(comps))
    names = fieldnames(typeof(comps))
    return NamedTuple{names}(vals)
end

function Base.show(io::IO, ::MIME"text/plain", x::IndexedRefView)
    !isvalid(x) && return print(io, "InvalidIndexView(ID = $(getfield(x, :id)))")
    isv, id = getfield(x, :isv), id(x)
    comps = getfield(isv, :components)
    i = getfield(x, :lasti)[]
    fields = NamedTuple(y => getfield(comps, y)[i] for y in fieldnames(typeof(comps)))
    return print(io, "IndexedView$fields")
end

include("dict.jl")

end
