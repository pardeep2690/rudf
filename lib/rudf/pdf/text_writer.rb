# frozen_string_literal: true

require_relative "standard_font"

module RUDF
  module PDF
    # Accumulates content-stream drawing operators for text, tracking which
    # standard fonts are used so a matching /Font resource can be emitted.
    #
    # Coordinates passed to {#draw_line} are in PDF user space (origin at the
    # bottom-left, y increasing upward); {TextLayout} converts from the
    # top-left page coordinates the public API uses.
    class TextContent
      def initialize
        @ops = +"".b
        @fonts = {} # resource name (e.g. "F1") => base font name
        @by_base = {} # base font name => resource name
      end

      # Map of resource name => base font name used by this content.
      attr_reader :fonts

      # Emit one line of text at baseline (+x+, +y+) in the given font/size.
      def draw_line(x, y, text, font, size, color = nil)
        name = resource_name_for(font.base)
        @ops << "q\n"
        @ops << color_op(color) if color
        @ops << format("BT /%s %s Tf %s %s Td (%s) Tj ET\n",
                       name, num(size), num(x), num(y), escape(text))
        @ops << "Q\n"
        self
      end

      # The assembled content-stream bytes.
      def to_s
        @ops
      end
      alias bytes to_s

      def empty?
        @ops.empty?
      end

      private

      def resource_name_for(base)
        return @by_base[base] if @by_base.key?(base)

        name = "F#{@fonts.length + 1}"
        @fonts[name] = base
        @by_base[base] = name
        name
      end

      def color_op(color)
        r, g, b = color
        format("%s %s %s rg\n", num(r), num(g), num(b))
      end

      def num(value)
        f = value.to_f
        f == f.to_i ? f.to_i.to_s : format("%.4f", f).sub(/0+\z/, "").sub(/\.\z/, "")
      end

      def escape(text)
        text.to_s.gsub("\\", "\\\\\\\\").gsub("(", "\\(").gsub(")", "\\)")
      end
    end

    # Lays out (optionally wrapped) text inside a rectangle and drives a
    # {TextContent} to draw it, handling horizontal alignment and vertical
    # positioning within the box. This is the shared core behind both the
    # {RUDF::Writer} and in-place text stamping.
    module TextLayout
      module_function

      # Place +text+ inside +rect+ (a top-left-origin [x0, y0, x1, y1]).
      #
      # @param align  [:left, :center, :right]
      # @param valign [:top, :center, :bottom]
      # @return [Array<Float>] the [x0, y0, x1, y1] bounds actually used
      def place(content:, rect:, text:, font:, size:, page_height:,
                align: :left, valign: :top, color: nil, line_spacing: 1.2)
        x0, y0, x1, y1 = rect
        box_w = x1 - x0
        box_h = y1 - y0

        lines = wrap(text, font, size, box_w)
        line_h = size * line_spacing
        total_h = lines.length * line_h

        start_top =
          case valign
          when :center then y0 + ((box_h - total_h) / 2.0)
          when :bottom then y1 - total_h
          else y0
          end

        used_x0 = x1
        used_x1 = x0
        lines.each_with_index do |line, i|
          line_w = font.text_width(line, size)
          x =
            case align
            when :center then x0 + ((box_w - line_w) / 2.0)
            when :right then x1 - line_w
            else x0
            end
          baseline_top = start_top + (i * line_h) + (size * 0.8) # ~ascent
          content.draw_line(x, page_height - baseline_top, line, font, size, color)
          used_x0 = [used_x0, x].min
          used_x1 = [used_x1, x + line_w].max
        end

        [used_x0, start_top, used_x1, start_top + total_h]
      end

      # Greedy word wrap to +max_width+; also honours explicit newlines. When a
      # single word is wider than the box it is kept on its own line.
      def wrap(text, font, size, max_width)
        return [""] if text.nil? || text.empty?

        out = []
        text.to_s.split("\n", -1).each do |paragraph|
          words = paragraph.split(/ /)
          line = +""
          words.each do |word|
            candidate = line.empty? ? word : "#{line} #{word}"
            if max_width.positive? && font.text_width(candidate, size) > max_width && !line.empty?
              out << line
              line = word.dup
            else
              line = candidate
            end
          end
          out << line
        end
        out
      end
    end
  end
end
