####################
# value extraction #
####################

@inline extract_value!(::Type{T}, out::DiffResult, ydual) where {T} =
    DiffResults.value!(d -> value(T,d), out, ydual)
@inline extract_value!(::Type{T}, out, ydual) where {T} = out # ???

@inline function extract_value!(::Type{T}, out, y, ydual) where {T}
    map!(d -> value(T,d), y, ydual)
    copy_value!(out, y)
end

@inline copy_value!(out::DiffResult, y) = DiffResults.value!(out, y)
@inline copy_value!(out, y) = out

###################################
# vector mode function evaluation #
###################################

@generated function dualize(::Type{T}, x::StaticArray) where T
    N = length(x)
    dx = Expr(:tuple, [:(Dual{T}(x[$i], chunk, Val{$i}())) for i in 1:N]...)
    V = StaticArrays.similar_type(x, Dual{T,eltype(x),N,eltype(x)})
    return quote
        chunk = Chunk{$N}()
        $(Expr(:meta, :inline))
        return $V($(dx))
    end
end

@inline static_dual_eval(::Type{T}, f, x::StaticArray) where T = f(dualize(T, x))

function vector_mode_dual_eval(f::F, x, cfg::Union{JacobianConfig,GradientConfig}) where {F}
    xdual = cfg.duals
    seed!(xdual, x, cfg.seeds)
    return f(xdual)
end

function vector_mode_dual_eval(f!::F, y, x, cfg::JacobianConfig) where {F}
    ydual, xdual = cfg.duals
    seed!(xdual, x, cfg.seeds)
    seed!(ydual, y)
    f!(ydual, xdual)
    return ydual
end

##################################
# seed construction/manipulation #
##################################

@generated function construct_seeds(::Type{Partials{N,V}}) where {N,V}
    return Expr(:tuple, [:(single_seed(Partials{N,V}, Val{$i}())) for i in 1:N]...)
end

function seed!(duals::AbstractArray{Dual{T,V,N,P}}, x,
               seed::Partials{N,P} = zero(Partials{N,P})) where {T,V,N,P}
    for i in eachindex(duals)
        duals[i] = Dual{T,V,N,P}(x[i], seed)
    end
    return duals
end

function seed!(duals::AbstractArray{Dual{T,V,N,P}}, x,
               seeds::NTuple{N,Partials{N,P}}) where {T,V,N,P}
    for i in 1:N
        duals[i] = Dual{T,V,N,P}(x[i], seeds[i])
    end
    return duals
end

function seed!(duals::AbstractArray{Dual{T,V,N,P}}, x, index,
               seed::Partials{N,P} = zero(Partials{N,P})) where {T,V,N,P}
    offset = index - 1
    for i in 1:N
        j = i + offset
        duals[j] = Dual{T,V,N,P}(x[j], seed)
    end
    return duals
end

function seed!(duals::AbstractArray{Dual{T,V,N,P}}, x, index,
               seeds::NTuple{N,Partials{N,P}}, chunksize = N) where {T,V,N,P}
    offset = index - 1
    for i in 1:chunksize
        j = i + offset
        duals[j] = Dual{T,V,N,P}(x[j], seeds[i])
    end
    return duals
end
