# To add support for loading/storing...
@inline function load(p::Ptr{UInt}, ::Type{T}) where {T}
    reinterpret(T, vload(p))
end
@inline function store!(p::Ptr{UInt}, x)
    vstore!(p, reinterpret(UInt, x))
end

@inline load(p::Ptr{UInt}, ::Type{StaticInt{N}}, i) where {N} = i, StaticInt{N}()
@inline store!(p::Ptr{UInt}, ::StaticInt, i) = i





@generated function load(p::Ptr{UInt}, ::Type{StridedPointer{T,N,C,B,R,X,O}}, i) where {T,N,C,B,R,X,O}
    q = quote
        $(Expr(:meta,:inline))
        i, ptr = load(p, Ptr{$T}, i)
    end
    xt = Expr(:tuple)
    Xp = X.parameters
    for n ∈ 1:N
        x = Symbol(:x_,n)
        push!(xt.args, x)
        push!(q.args, :((i, $x) = load(p, $(Xp[n]), i)))
    end
    ot = Expr(:tuple)
    Op = O.parameters
    for n ∈ 1:N
        o = Symbol(:o_,n)
        push!(ot.args, o)
        push!(q.args, :((i, $o) = load(p, $(Op[n]), i)))
    end
    push!(q.args, :((i, StridedPointer{$T,$N,$C,$B,$R}(ptr, $xt, $ot))))
    q
end
@generated function store!(p::Ptr{UInt}, ptr::StridedPointer{T,N,C,B,R,X,O}, i) where {T,N,C,B,R,X,O}
    q = quote
        $(Expr(:meta,:inline))
        i = store!(p, pointer(ptr), i)
        strd = strides(ptr)
        offs = offsets(ptr)
    end
    for n ∈ 1:N
        push!(q.args, :(i = store!(p, strd[$n], i)))
    end
    for n ∈ 1:N
        push!(q.args, :(i = store!(p, offs[$n], i)))
    end
    push!(q.args, :i)
    q
end

@inline function load(p::Ptr{UInt}, ::Type{T}, i) where {T}
    i += 1
    i, load(p + i * sizeof(UInt), T)
end
@inline function store!(p::Ptr{UInt}, x, i)
    store!(p + sizeof(UInt)*(i += 1), x)
    i
end

@generated function load(p::Ptr{UInt}, ::Type{T}, i) where {T<:Tuple}
    q = Expr(:block, Expr(:meta,:inline))
    tup = Expr(:tuple)
    for (i,t) ∈ enumerate(T.parameters)
        ln = Symbol(:l_,i)
        push!(tup.args, ln)
        push!(q.args, :((i,$ln) = load(p, $t, i)))
    end
    push!(q.args, :(i, $tup))
    q
end

@inline function store!(p::Ptr{UInt}, tup::Tuple{A,B,Vararg{Any,N}}, i) where {A,B,N}
    i = store!(p, first(tup), i)
    store!(p, Base.tail(tup), i)
end
@inline function store!(p::Ptr{UInt}, tup::Tuple{A}, i) where {A}
    store!(p, first(tup), i)
end
@inline store!(p::Ptr{UInt}, tup::Tuple{}, i) = i
