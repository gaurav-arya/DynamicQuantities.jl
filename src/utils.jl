import Tricks: static_fieldnames
import LinearAlgebra: norm
import Compat: allequal

function map_dimensions(f::F, args::AbstractDimensions...) where {F<:Function}
    dimension_type = promote_type(typeof(args).parameters...)
    dimension_names = static_fieldnames(dimension_type)
    return new_dimensions(
        dimension_type,
        (
            f((getproperty(arg, dim) for arg in args)...)
            for dim in dimension_names
        )...
    )
end
@generated function all_dimensions(f::F, args::AbstractDimensions...) where {F<:Function}
    # Test a function over all dimensions
    output = Expr(:&&)
    dimension_type = promote_type(args...)
    for dim in Base.fieldnames(dimension_type)
        f_expr = :(f())
        for i=1:length(args)
            push!(f_expr.args, :(args[$i].$dim))
        end
        push!(output.args, f_expr)
    end
    return output
end

Base.float(q::AbstractQuantity{T}) where {T<:AbstractFloat} = convert(T, q)
Base.convert(::Type{T}, q::AbstractQuantity) where {T<:Real} =
    let
        @assert iszero(dimension(q)) "$(typeof(q)): $(q) has dimensions! Use `ustrip` instead."
        return convert(T, ustrip(q))
    end

Base.keys(d::AbstractDimensions) = static_fieldnames(typeof(d))
Base.getindex(d::AbstractDimensions, k::Symbol) = getfield(d, k)

# Compatibility with `.*`
Base.length(::AbstractQuantity) = 1
Base.iterate(qd::AbstractQuantity) = (qd, nothing)
Base.iterate(::AbstractQuantity, ::Nothing) = nothing

# Numeric checks
Base.isapprox(l::AbstractQuantity, r::AbstractQuantity; kws...) = isapprox(ustrip(l), ustrip(r); kws...) && dimension(l) == dimension(r)
Base.isapprox(l, r::AbstractQuantity; kws...) = iszero(dimension(r)) ? isapprox(l, ustrip(r); kws...) : throw(DimensionError(l, r))
Base.isapprox(l::AbstractQuantity, r; kws...) = iszero(dimension(l)) ? isapprox(ustrip(l), r; kws...) : throw(DimensionError(l, r))
Base.iszero(d::AbstractDimensions) = all_dimensions(iszero, d)
Base.:(==)(l::AbstractDimensions, r::AbstractDimensions) = all_dimensions(==, l, r)
Base.:(==)(l::AbstractQuantity, r::AbstractQuantity) = ustrip(l) == ustrip(r) && dimension(l) == dimension(r)
Base.:(==)(l, r::AbstractQuantity) = ustrip(l) == ustrip(r) && iszero(dimension(r))
Base.:(==)(l::AbstractQuantity, r) = ustrip(l) == ustrip(r) && iszero(dimension(l))
Base.isless(l::AbstractQuantity, r::AbstractQuantity) = dimension(l) == dimension(r) ? isless(ustrip(l), ustrip(r)) : throw(DimensionError(l, r))
Base.isless(l::AbstractQuantity, r) = iszero(dimension(l)) ? isless(ustrip(l), r) : throw(DimensionError(l, r))
Base.isless(l, r::AbstractQuantity) = iszero(dimension(r)) ? isless(l, ustrip(r)) : throw(DimensionError(l, r))

# Get rid of method ambiguities:
Base.isless(::AbstractQuantity, ::Missing) = missing
Base.isless(::Missing, ::AbstractQuantity) = missing
Base.:(==)(::AbstractQuantity, ::Missing) = missing
Base.:(==)(::Missing, ::AbstractQuantity) = missing
Base.isapprox(::AbstractQuantity, ::Missing; kws...) = missing
Base.isapprox(::Missing, ::AbstractQuantity; kws...) = missing

Base.:(==)(::AbstractQuantity, ::WeakRef) = error("Cannot compare a quantity to a weakref")
Base.:(==)(::WeakRef, ::AbstractQuantity) = error("Cannot compare a weakref to a quantity")


# Simple flags:
for f in (:iszero, :isfinite, :isinf, :isnan, :isreal)
    @eval Base.$f(q::AbstractQuantity) = $f(ustrip(q))
end

# Simple operations which return a full quantity (same dimensions)
norm(q::AbstractQuantity, p::Real=2) = new_quantity(typeof(q), norm(ustrip(q), p), dimension(q))
norm(q::AbstractArray{<:AbstractQuantity}, p::Real=2) = new_quantity(eltype(q), norm(ustrip(q), p), dimension(q))
for f in (:real, :imag, :conj, :adjoint, :unsigned, :nextfloat, :prevfloat)
    @eval Base.$f(q::AbstractQuantity) = new_quantity(typeof(q), $f(ustrip(q)), dimension(q))
end

# Base.one, typemin, typemax
for f in (:one, :typemin, :typemax)
    @eval begin
        Base.$f(::Type{Q}) where {T,D,Q<:AbstractQuantity{T,D}} = new_quantity(Q, $f(T), D)
        Base.$f(::Type{Q}) where {T,Q<:AbstractQuantity{T}} = $f(constructor_of(Q){T, DEFAULT_DIM_TYPE})
        Base.$f(::Type{Q}) where {Q<:AbstractQuantity} = $f(Q{DEFAULT_VALUE_TYPE, DEFAULT_DIM_TYPE})
    end
    if f == :one  # Return empty dimensions, as should be multiplicative identity.
        @eval Base.$f(q::Q) where {Q<:AbstractQuantity} = new_quantity(Q, $f(ustrip(q)), one(dimension(q)))
    else
        @eval Base.$f(q::Q) where {Q<:AbstractQuantity} = new_quantity(Q, $f(ustrip(q)), dimension(q))
    end
end
Base.one(::Type{D}) where {D<:AbstractDimensions} = D()
Base.one(::D) where {D<:AbstractDimensions} = one(D)

# Additive identities (zero)
Base.zero(q::Q) where {Q<:AbstractQuantity} = new_quantity(Q, zero(ustrip(q)), dimension(q))
Base.zero(::AbstractDimensions) = error("There is no such thing as an additive identity for a `AbstractDimensions` object, as + is only defined for `AbstractQuantity`.")
Base.zero(::Type{<:AbstractQuantity}) = error("Cannot create an additive identity for a `AbstractQuantity` type, as the dimensions are unknown. Please use `zero(::AbstractQuantity)` instead.")
Base.zero(::Type{<:AbstractDimensions}) = error("There is no such thing as an additive identity for a `AbstractDimensions` type, as + is only defined for `AbstractQuantity`.")

# Dimensionful 1 (oneunit)
Base.oneunit(q::Q) where {Q<:AbstractQuantity} = new_quantity(Q, oneunit(ustrip(q)), dimension(q))
Base.oneunit(::AbstractDimensions) = error("There is no such thing as a dimensionful 1 for a `AbstractDimensions` object, as + is only defined for `AbstractQuantity`.")
Base.oneunit(::Type{<:AbstractQuantity}) = error("Cannot create a dimensionful 1 for a `AbstractQuantity` type without knowing the dimensions. Please use `oneunit(::AbstractQuantity)` instead.")
Base.oneunit(::Type{<:AbstractDimensions}) = error("There is no such thing as a dimensionful 1 for a `AbstractDimensions` type, as + is only defined for `AbstractQuantity`.")

Base.show(io::IO, d::AbstractDimensions) =
    let tmp_io = IOBuffer()
        for k in filter(k -> !iszero(d[k]), keys(d))
            print(tmp_io, dimension_name(d, k))
            isone(d[k]) || pretty_print_exponent(tmp_io, d[k])
            print(tmp_io, " ")
        end
        s = String(take!(tmp_io))
        s = replace(s, r"^\s*" => "")
        s = replace(s, r"\s*$" => "")
        print(io, s)
    end
Base.show(io::IO, q::AbstractQuantity{<:Real}) = print(io, ustrip(q), " ", dimension(q))
Base.show(io::IO, q::AbstractQuantity) = print(io, "(", ustrip(q), ") ", dimension(q))

function dimension_name(::AbstractDimensions, k::Symbol)
    default_dimensions = (length="m", mass="kg", time="s", current="A", temperature="K", luminosity="cd", amount="mol")
    return get(default_dimensions, k, string(k))
end

string_rational(x) = isinteger(x) ? string(round(Int, x)) : string(x)
pretty_print_exponent(io::IO, x) = print(io, to_superscript(string_rational(x)))
const SUPERSCRIPT_MAPPING = ('⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹')
const INTCHARS = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9')
to_superscript(s::AbstractString) = join(
    map(replace(s, "//" => "ᐟ")) do c
        if c ∈ INTCHARS
            SUPERSCRIPT_MAPPING[parse(Int, c)+1]
        elseif c == '-'
            '⁻'
        else
            c
        end
    end
)

tryrationalize(::Type{R}, x::R) where {R} = x
tryrationalize(::Type{R}, x::Union{Rational,Integer}) where {R} = convert(R, x)
tryrationalize(::Type{R}, x) where {R} = isinteger(x) ? convert(R, round(Int, x)) : convert(R, rationalize(Int, x))

Base.showerror(io::IO, e::DimensionError) = print(io, "DimensionError: ", e.q1, " and ", e.q2, " have incompatible dimensions")

Base.convert(::Type{Q}, q::AbstractQuantity) where {Q<:AbstractQuantity} = q
Base.convert(::Type{Q}, q::AbstractQuantity) where {T,Q<:AbstractQuantity{T}} = new_quantity(Q, convert(T, ustrip(q)), dimension(q))
Base.convert(::Type{Q}, q::AbstractQuantity) where {T,D,Q<:AbstractQuantity{T,D}} = new_quantity(Q, convert(T, ustrip(q)), convert(D, dimension(q)))

Base.convert(::Type{D}, d::AbstractDimensions) where {D<:AbstractDimensions} = d
Base.convert(::Type{D}, d::AbstractDimensions) where {R,D<:AbstractDimensions{R}} = D(d)

Base.copy(q::Q) where {Q<:AbstractQuantity} = new_quantity(Q, copy(ustrip(q)), copy(dimension(q)))

"""
    ustrip(q::AbstractQuantity)

Remove the units from a quantity.
"""
ustrip(q::AbstractQuantity) = q.value
ustrip(::AbstractDimensions) = error("Cannot remove units from an `AbstractDimensions` object.")
ustrip(aq::AbstractArray{<:AbstractQuantity}) = ustrip.(aq)
ustrip(q) = q

"""
    dimension(q::AbstractQuantity)

Get the dimensions of a quantity, returning an `AbstractDimensions` object.
"""
dimension(q::AbstractQuantity) = q.dimensions
dimension(d::AbstractDimensions) = d
dimension(aq::AbstractArray{<:AbstractQuantity}) = allequal(dimension.(aq)) ? dimension(first(aq)) : throw(DimensionError(aq[begin], aq[begin+1:end]))

"""
    ulength(q::AbstractQuantity)
    ulength(d::AbstractDimensions)

Get the length dimension of a quantity (e.g., meters^(ulength)).
"""
ulength(q::AbstractQuantity) = ulength(dimension(q))
ulength(d::AbstractDimensions) = d.length

"""
    umass(q::AbstractQuantity)
    umass(d::AbstractDimensions)

Get the mass dimension of a quantity (e.g., kg^(umass)).
"""
umass(q::AbstractQuantity) = umass(dimension(q))
umass(d::AbstractDimensions) = d.mass

"""
    utime(q::AbstractQuantity)
    utime(d::AbstractDimensions)

Get the time dimension of a quantity (e.g., s^(utime))
"""
utime(q::AbstractQuantity) = utime(dimension(q))
utime(d::AbstractDimensions) = d.time

"""
    ucurrent(q::AbstractQuantity)
    ucurrent(d::AbstractDimensions)

Get the current dimension of a quantity (e.g., A^(ucurrent)).
"""
ucurrent(q::AbstractQuantity) = ucurrent(dimension(q))
ucurrent(d::AbstractDimensions) = d.current

"""
    utemperature(q::AbstractQuantity)
    utemperature(d::AbstractDimensions)

Get the temperature dimension of a quantity (e.g., K^(utemperature)).
"""
utemperature(q::AbstractQuantity) = utemperature(dimension(q))
utemperature(d::AbstractDimensions) = d.temperature

"""
    uluminosity(q::AbstractQuantity)
    uluminosity(d::AbstractDimensions)

Get the luminosity dimension of a quantity (e.g., cd^(uluminosity)).
"""
uluminosity(q::AbstractQuantity) = uluminosity(dimension(q))
uluminosity(d::AbstractDimensions) = d.luminosity

"""
    uamount(q::AbstractQuantity)
    uamount(d::AbstractDimensions)

Get the amount dimension of a quantity (e.g., mol^(uamount)).
"""
uamount(q::AbstractQuantity) = uamount(dimension(q))
uamount(d::AbstractDimensions) = d.amount
