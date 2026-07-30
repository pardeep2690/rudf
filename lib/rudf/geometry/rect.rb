# frozen_string_literal: true

module RUDF
  # An axis-aligned rectangle, ported from +fitz.Rect+.
  #
  # A rectangle is defined by its top-left +(x0, y0)+ and bottom-right
  # +(x1, y1)+ corners. As in PyMuPDF, a rectangle is "finite" when
  # +x0 <= x1+ and +y0 <= y1+; otherwise it is considered empty/invalid until
  # normalized.
  class Rect
    attr_accessor :x0, :y0, :x1, :y1

    # Accepts +Rect.new(x0, y0, x1, y1)+, +Rect.new(rect)+,
    # +Rect.new([x0, y0, x1, y1])+ or two +Point+ corners.
    def initialize(*args)
      case args.length
      when 0
        assign(0.0, 0.0, 0.0, 0.0)
      when 1
        arg = args[0]
        case arg
        when Rect
          assign(arg.x0, arg.y0, arg.x1, arg.y1)
        when Array
          assign(*arg)
        else
          raise ArgumentError, "cannot build Rect from #{arg.inspect}"
        end
      when 2
        p0 = Point.new(args[0])
        p1 = Point.new(args[1])
        assign(p0.x, p0.y, p1.x, p1.y)
      when 4
        assign(*args)
      else
        raise ArgumentError, "Rect accepts 0, 1, 2 or 4 arguments (got #{args.length})"
      end
    end

    def width
      [0.0, @x1 - @x0].max
    end

    def height
      [0.0, @y1 - @y0].max
    end

    # Signed area (may be negative for non-normalized rectangles).
    def area
      (@x1 - @x0) * (@y1 - @y0)
    end
    alias get_area area

    def empty?
      @x0 >= @x1 || @y0 >= @y1
    end

    def valid?
      @x0 <= @x1 && @y0 <= @y1
    end

    def infinite?
      @x0 == -Float::INFINITY || @y0 == -Float::INFINITY ||
        @x1 == Float::INFINITY || @y1 == Float::INFINITY
    end

    # Corner points.
    def top_left
      Point.new(@x0, @y0)
    end
    alias tl top_left

    def top_right
      Point.new(@x1, @y0)
    end
    alias tr top_right

    def bottom_left
      Point.new(@x0, @y1)
    end
    alias bl bottom_left

    def bottom_right
      Point.new(@x1, @y1)
    end
    alias br bottom_right

    # Reorder corners so the rectangle becomes valid. Returns +self+.
    def normalize
      @x0, @x1 = @x1, @x0 if @x0 > @x1
      @y0, @y1 = @y1, @y0 if @y0 > @y1
      self
    end

    # True if +item+ (a Point, Rect or coordinate pair) lies within the
    # rectangle (inclusive of the border).
    def contains?(item)
      case item
      when Rect
        return true if item.empty?

        item.x0 >= @x0 && item.x1 <= @x1 && item.y0 >= @y0 && item.y1 <= @y1
      when Point
        item.x >= @x0 && item.x <= @x1 && item.y >= @y0 && item.y <= @y1
      when Array
        contains?(Point.new(item))
      else
        raise ArgumentError, "cannot test containment of #{item.inspect}"
      end
    end
    alias contains contains?

    # Enlarge the rectangle to include +point+. Returns +self+.
    def include_point(point)
      point = Point.new(point)
      if empty?
        assign(point.x, point.y, point.x, point.y)
      else
        @x0 = [@x0, point.x].min
        @y0 = [@y0, point.y].min
        @x1 = [@x1, point.x].max
        @y1 = [@y1, point.y].max
      end
      self
    end

    # Enlarge the rectangle to include +rect+. Returns +self+.
    def include_rect(rect)
      rect = Rect.new(rect)
      return self if rect.empty?
      return replace_with(rect) if empty?

      @x0 = [@x0, rect.x0].min
      @y0 = [@y0, rect.y0].min
      @x1 = [@x1, rect.x1].max
      @y1 = [@y1, rect.y1].max
      self
    end

    # Intersect with +rect+ in place. Returns +self+.
    def intersect(rect)
      rect = Rect.new(rect)
      @x0 = [@x0, rect.x0].max
      @y0 = [@y0, rect.y0].max
      @x1 = [@x1, rect.x1].min
      @y1 = [@y1, rect.y1].min
      self
    end

    # Non-mutating union (+|+) and intersection (+&+).
    def |(other)
      Rect.new(self).include_rect(other)
    end

    def &(other)
      Rect.new(self).intersect(other)
    end

    def intersects?(other)
      !(Rect.new(self) & other).empty?
    end

    # Apply an affine Matrix to the rectangle, returning +self+ after
    # transforming all four corners and taking their bounding box.
    def transform(matrix)
      matrix = Matrix.new(matrix) unless matrix.is_a?(Matrix)
      corners = [top_left, top_right, bottom_left, bottom_right].map { |p| p.transform(matrix) }
      xs = corners.map(&:x)
      ys = corners.map(&:y)
      assign(xs.min, ys.min, xs.max, ys.max)
      self
    end

    # The smallest IRect containing this rectangle.
    def round
      IRect.new(@x0.floor, @y0.floor, @x1.ceil, @y1.ceil)
    end
    alias irect round

    def ==(other)
      return false unless other.is_a?(Rect)

      to_a == other.to_a
    end
    alias eql? ==

    def hash
      to_a.hash
    end

    def to_a
      [@x0, @y0, @x1, @y1]
    end
    alias to_ary to_a

    def [](index)
      to_a[index]
    end

    def to_s
      "Rect(#{to_a.map { |v| fmt(v) }.join(', ')})"
    end
    alias inspect to_s

    private

    def assign(x0, y0, x1, y1)
      @x0 = x0.to_f
      @y0 = y0.to_f
      @x1 = x1.to_f
      @y1 = y1.to_f
    end

    def replace_with(rect)
      assign(rect.x0, rect.y0, rect.x1, rect.y1)
      self
    end

    def fmt(value)
      value == value.to_i ? value.to_i.to_s : value.to_s
    end
  end
end
