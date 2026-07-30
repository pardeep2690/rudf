# frozen_string_literal: true

module RUDF
  # A 2-by-3 affine transformation matrix, ported from +fitz.Matrix+.
  #
  # The six components +[a, b, c, d, e, f]+ represent the transform
  #
  #   x' = a*x + c*y + e
  #   y' = b*x + d*y + f
  #
  # Several convenience constructors mirror PyMuPDF:
  #
  #   Matrix.new                 # zero matrix (0,0,0,0,0,0)
  #   Matrix.new(2, 3)           # scale x by 2, y by 3
  #   Matrix.new(30)             # rotate 30 degrees
  #   Matrix.new(a,b,c,d,e,f)    # full matrix
  #   RUDF::IDENTITY             # the identity matrix (1,0,0,1,0,0)
  class Matrix
    attr_accessor :a, :b, :c, :d, :e, :f

    def initialize(*args)
      case args.length
      when 0
        @a = @b = @c = @d = @e = @f = 0.0
      when 1
        arg = args[0]
        case arg
        when Matrix
          assign(arg.a, arg.b, arg.c, arg.d, arg.e, arg.f)
        when Array
          assign(*arg)
        when Numeric
          # A single number is a rotation by that many degrees.
          rad = arg * Math::PI / 180.0
          assign(Math.cos(rad), Math.sin(rad), -Math.sin(rad), Math.cos(rad), 0.0, 0.0)
        else
          raise ArgumentError, "cannot build Matrix from #{arg.inspect}"
        end
      when 2
        # Two numbers form a scaling matrix.
        assign(args[0], 0.0, 0.0, args[1], 0.0, 0.0)
      when 6
        assign(*args)
      else
        raise ArgumentError, "Matrix accepts 0, 1, 2 or 6 arguments (got #{args.length})"
      end
    end

    # The identity matrix (1, 0, 0, 1, 0, 0).
    def self.identity
      new(1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
    end

    # A rotation matrix by +degrees+.
    def self.rotate(degrees)
      new(degrees)
    end

    # A scaling matrix.
    def self.scale(sx, sy)
      new(sx, sy)
    end

    # A translation matrix.
    def self.translate(tx, ty)
      new(1.0, 0.0, 0.0, 1.0, tx.to_f, ty.to_f)
    end

    # Matrix determinant / area-scaling factor.
    def norm
      (@a * @d) - (@b * @c)
    end
    alias determinant norm

    def identity?
      @a == 1.0 && @b.zero? && @c.zero? && @d == 1.0 && @e.zero? && @f.zero?
    end

    def invertible?
      norm != 0.0
    end

    # The inverse transform. Raises for singular matrices.
    def inverse
      det = norm
      raise Error, "matrix is not invertible" if det.zero?

      ia =  @d / det
      ib = -@b / det
      ic = -@c / det
      id =  @a / det
      ie = -((@e * ia) + (@f * ic))
      if_ = -((@e * ib) + (@f * id))
      Matrix.new(ia, ib, ic, id, ie, if_)
    end
    alias invert inverse

    # Matrix concatenation. +m1 * m2+ yields the transform that applies +m1+
    # first and then +m2+ (same order as PyMuPDF's +Matrix.concat+).
    def *(other)
      other = Matrix.new(other) unless other.is_a?(Matrix)
      Matrix.new(
        (@a * other.a) + (@b * other.c),
        (@a * other.b) + (@b * other.d),
        (@c * other.a) + (@d * other.c),
        (@c * other.b) + (@d * other.d),
        (@e * other.a) + (@f * other.c) + other.e,
        (@e * other.b) + (@f * other.d) + other.f
      )
    end

    # In-place style pre-concatenation helpers. Each returns +self+ after
    # pre-multiplying the corresponding transform, mirroring +fitz.Matrix+.
    def pre_scale(sx, sy)
      @a *= sx
      @b *= sx
      @c *= sy
      @d *= sy
      self
    end

    def pre_translate(tx, ty)
      @e += (tx * @a) + (ty * @c)
      @f += (tx * @b) + (ty * @d)
      self
    end

    def pre_rotate(degrees)
      degrees %= 360
      degrees += 360 if degrees < 0
      case degrees
      when 0
        # no-op
      when 90
        rotate_by(0.0, 1.0, -1.0, 0.0)
      when 180
        rotate_by(-1.0, 0.0, 0.0, -1.0)
      when 270
        rotate_by(0.0, -1.0, 1.0, 0.0)
      else
        rad = degrees * Math::PI / 180.0
        s = Math.sin(rad)
        cc = Math.cos(rad)
        rotate_by(cc, s, -s, cc)
      end
      self
    end

    def pre_shear(h, v)
      na = @a + (v * @c)
      nb = @b + (v * @d)
      @c += h * @a
      @d += h * @b
      @a = na
      @b = nb
      self
    end

    def concat(m1, m2)
      result = (m1.is_a?(Matrix) ? m1 : Matrix.new(m1)) * (m2.is_a?(Matrix) ? m2 : Matrix.new(m2))
      assign(result.a, result.b, result.c, result.d, result.e, result.f)
      self
    end

    def ==(other)
      return false unless other.is_a?(Matrix)

      to_a == other.to_a
    end
    alias eql? ==

    def hash
      to_a.hash
    end

    def to_a
      [@a, @b, @c, @d, @e, @f]
    end
    alias to_ary to_a

    def [](index)
      to_a[index]
    end

    def to_s
      "Matrix(#{to_a.map { |v| fmt(v) }.join(', ')})"
    end
    alias inspect to_s

    private

    def assign(a, b, c, d, e, f)
      @a = a.to_f
      @b = b.to_f
      @c = c.to_f
      @d = d.to_f
      @e = e.to_f
      @f = f.to_f
    end

    def rotate_by(a, b, c, d)
      na = (@a * a) + (@c * b)
      nb = (@b * a) + (@d * b)
      nc = (@a * c) + (@c * d)
      nd = (@b * c) + (@d * d)
      @a = na
      @b = nb
      @c = nc
      @d = nd
    end

    def fmt(value)
      value == value.to_i ? value.to_i.to_s : format("%.4g", value)
    end
  end

  # The identity transformation matrix, analogous to +fitz.Identity+.
  IDENTITY = Matrix.identity.freeze
end
