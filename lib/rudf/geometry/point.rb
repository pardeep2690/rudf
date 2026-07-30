# frozen_string_literal: true

module RUDF
  # A 2-dimensional point, ported from +fitz.Point+.
  #
  # Coordinates follow the PDF / MuPDF convention. A Point supports the same
  # arithmetic and transformation operations as its PyMuPDF counterpart.
  #
  #   RUDF::Point.new(1, 2) + RUDF::Point.new(3, 4)  #=> Point(4.0, 6.0)
  #   RUDF::Point.new(1, 0) * RUDF::Matrix.new(90)   # rotate 90 degrees
  class Point
    attr_accessor :x, :y

    # Accepts +Point.new+, +Point.new(x, y)+, +Point.new(point)+ or
    # +Point.new([x, y])+.
    def initialize(x = 0.0, y = nil)
      if y.nil?
        case x
        when Point
          @x = x.x.to_f
          @y = x.y.to_f
        when Array
          @x = x[0].to_f
          @y = x[1].to_f
        when Numeric
          @x = x.to_f
          @y = 0.0
        else
          raise ArgumentError, "cannot build Point from #{x.inspect}"
        end
      else
        @x = x.to_f
        @y = y.to_f
      end
    end

    # The Euclidean length of the point interpreted as a vector.
    def abs
      Math.sqrt((@x * @x) + (@y * @y))
    end
    alias norm abs

    # A point of unit length pointing in the same direction (the zero vector
    # maps to itself).
    def unit
      len = abs
      return Point.new(0.0, 0.0) if len.zero?

      Point.new(@x / len, @y / len)
    end

    # Absolute value of both coordinates.
    def abs_unit
      Point.new(@x.abs, @y.abs).unit
    end

    # Euclidean distance to another point.
    def distance_to(other)
      other = Point.new(other)
      Math.sqrt(((@x - other.x)**2) + ((@y - other.y)**2))
    end

    def +(other)
      apply(other) { |a, b| a + b }
    end

    def -(other)
      apply(other) { |a, b| a - b }
    end

    # Multiplication by a scalar or a Matrix (the latter transforms the point).
    def *(other)
      if other.is_a?(Matrix)
        transform(other)
      elsif other.is_a?(Numeric)
        Point.new(@x * other, @y * other)
      else
        apply(other) { |a, b| a * b }
      end
    end

    def /(other)
      if other.is_a?(Matrix)
        transform(other.inverse)
      elsif other.is_a?(Numeric)
        Point.new(@x / other, @y / other)
      else
        apply(other) { |a, b| a / b }
      end
    end

    # Apply an affine Matrix, returning a new Point.
    def transform(matrix)
      matrix = Matrix.new(matrix) unless matrix.is_a?(Matrix)
      nx = (@x * matrix.a) + (@y * matrix.c) + matrix.e
      ny = (@x * matrix.b) + (@y * matrix.d) + matrix.f
      Point.new(nx, ny)
    end

    def ==(other)
      return false unless other.is_a?(Point)

      @x == other.x && @y == other.y
    end
    alias eql? ==

    def hash
      [@x, @y].hash
    end

    def to_a
      [@x, @y]
    end
    alias to_ary to_a

    def [](index)
      to_a[index]
    end

    def to_s
      "Point(#{fmt(@x)}, #{fmt(@y)})"
    end
    alias inspect to_s

    private

    def apply(other)
      other = other.is_a?(Point) ? other : Point.new(other)
      Point.new(yield(@x, other.x), yield(@y, other.y))
    end

    def fmt(value)
      value == value.to_i ? value.to_i.to_s : value.to_s
    end
  end
end
