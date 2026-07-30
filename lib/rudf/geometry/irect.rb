# frozen_string_literal: true

require_relative "rect"

module RUDF
  # An integer-coordinate rectangle, ported from +fitz.IRect+.
  #
  # Behaves like {Rect} but all coordinates are truncated to integers on
  # assignment. Produced by {Rect#round} when a page or drawing needs pixel
  # boundaries.
  class IRect < Rect
    def width
      @x1 - @x0
    end

    def height
      @y1 - @y0
    end

    # The floating-point rectangle with the same coordinates.
    def rect
      Rect.new(@x0, @y0, @x1, @y1)
    end

    def top_left
      Point.new(@x0, @y0)
    end
    alias tl top_left

    def to_s
      "IRect(#{to_a.map(&:to_i).join(', ')})"
    end
    alias inspect to_s

    private

    def assign(x0, y0, x1, y1)
      @x0 = x0.to_i
      @y0 = y0.to_i
      @x1 = x1.to_i
      @y1 = y1.to_i
    end
  end
end
