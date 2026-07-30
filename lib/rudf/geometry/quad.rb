# frozen_string_literal: true

module RUDF
  # A quadrilateral defined by four corner points, ported from +fitz.Quad+.
  #
  # Unlike a {Rect}, a Quad can represent rotated or sheared regions, such as
  # the bounding area of rotated text. Corners are named +ul+ (upper-left),
  # +ur+ (upper-right), +ll+ (lower-left) and +lr+ (lower-right).
  class Quad
    attr_accessor :ul, :ur, :ll, :lr

    # Accepts four Points, another Quad, a Rect, or a flat array of four
    # +[x, y]+ pairs / eight numbers.
    def initialize(*args)
      case args.length
      when 0
        zero = Point.new(0, 0)
        assign(zero, zero, zero, zero)
      when 1
        arg = args[0]
        case arg
        when Quad
          assign(arg.ul, arg.ur, arg.ll, arg.lr)
        when Rect
          assign(arg.top_left, arg.top_right, arg.bottom_left, arg.bottom_right)
        when Array
          from_array(arg)
        else
          raise ArgumentError, "cannot build Quad from #{arg.inspect}"
        end
      when 4
        assign(Point.new(args[0]), Point.new(args[1]), Point.new(args[2]), Point.new(args[3]))
      else
        raise ArgumentError, "Quad accepts 0, 1 or 4 arguments (got #{args.length})"
      end
    end

    # The bounding rectangle that contains all four corners.
    def rect
      xs = [@ul.x, @ur.x, @ll.x, @lr.x]
      ys = [@ul.y, @ur.y, @ll.y, @lr.y]
      Rect.new(xs.min, ys.min, xs.max, ys.max)
    end

    # True when the quad is an axis-aligned rectangle.
    def rectangular?
      @ul.y == @ur.y && @ll.y == @lr.y && @ul.x == @ll.x && @ur.x == @lr.x
    end
    alias is_rectangular rectangular?

    def empty?
      rect.empty?
    end

    # Apply an affine Matrix to all corners, returning +self+.
    def transform(matrix)
      matrix = Matrix.new(matrix) unless matrix.is_a?(Matrix)
      @ul = @ul.transform(matrix)
      @ur = @ur.transform(matrix)
      @ll = @ll.transform(matrix)
      @lr = @lr.transform(matrix)
      self
    end

    def ==(other)
      return false unless other.is_a?(Quad)

      to_a == other.to_a
    end
    alias eql? ==

    def hash
      to_a.hash
    end

    def to_a
      [@ul.to_a, @ur.to_a, @ll.to_a, @lr.to_a]
    end

    def to_s
      "Quad(#{@ul}, #{@ur}, #{@ll}, #{@lr})"
    end
    alias inspect to_s

    private

    def assign(ul, ur, ll, lr)
      @ul = ul
      @ur = ur
      @ll = ll
      @lr = lr
    end

    def from_array(arr)
      points =
        if arr.length == 8
          arr.each_slice(2).map { |pair| Point.new(pair) }
        else
          arr.map { |p| Point.new(p) }
        end
      raise ArgumentError, "Quad needs four corner points" unless points.length == 4

      assign(*points)
    end
  end
end
