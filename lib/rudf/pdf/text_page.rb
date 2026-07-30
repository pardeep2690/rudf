# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"
require_relative "font"

module RUDF
  module PDF
    # Interprets a page content stream into structured text.
    #
    # The interpreter tracks the text and graphics state that PDF defines
    # (text matrix, line matrix, font, sizes, spacing and the CTM via
    # +q+/+Q+/+cm+) so it can place each glyph in device space. Glyphs are then
    # grouped into words, lines and blocks. All +Page#get_text+ modes are
    # rendered from this single structure, mirroring PyMuPDF's TextPage.
    #
    # Coordinates are reported with a top-left origin (y increasing downward),
    # matching PyMuPDF; the caller supplies the page height for the flip.
    class TextPage
      Char = Struct.new(:text, :x0, :y0, :x1, :y1, :ox, :oy, :font, :size, keyword_init: true)

      def initialize(content, resources:, resolver:, page_height:, page_width: nil)
        @content = content
        @resources = resources || {}
        @resolver = resolver
        @page_height = page_height
        @page_width = page_width
        @fonts = {}
        @chars = []
        interpret
        @blocks = group_blocks(@chars)
      end

      # Plain text with newlines between lines and blank lines between blocks.
      def text
        @blocks.map do |block|
          block.map { |line| line_text(line) }.join("\n")
        end.join("\n\n").gsub(/[ \t]+\n/, "\n").strip
      end

      # PyMuPDF-style word tuples: [x0, y0, x1, y1, word, block, line, wordno].
      def words
        out = []
        @blocks.each_with_index do |block, bno|
          block.each_with_index do |line, lno|
            split_words(line).each_with_index do |word, wno|
              bbox = union_bbox(word)
              out << [*bbox, word.map(&:text).join, bno, lno, wno]
            end
          end
        end
        out
      end

      # PyMuPDF-style block tuples: [x0, y0, x1, y1, text, block, type].
      def blocks
        @blocks.each_with_index.map do |block, bno|
          chars = block.flatten
          text = block.map { |line| line_text(line) }.join("\n")
          [*union_bbox(chars), text, bno, 0]
        end
      end

      # Nested dict form: blocks -> lines -> spans, each with bbox and text.
      def dict
        {
          width: page_width,
          height: @page_height,
          blocks: @blocks.each_with_index.map do |block, bno|
            {
              type: 0,
              number: bno,
              bbox: union_bbox(block.flatten),
              lines: block.map do |line|
                {
                  bbox: union_bbox(line),
                  spans: build_spans(line)
                }
              end
            }
          end
        }
      end

      private

      attr_reader :page_width

      # ---- content stream interpretation -------------------------------------

      def interpret
        lexer = Lexer.new(@content)
        parser = Parser.new(@content, lexer: lexer)
        operands = []

        # Graphics + text state.
        @ctm = RUDF::Matrix.identity
        @ctm_stack = []
        reset_text_state
        @tm = RUDF::Matrix.identity
        @tlm = RUDF::Matrix.identity

        loop do
          token = lexer.next_token
          break if token.type == :eof

          if token.type == :keyword
            execute(token.value, operands)
            operands = []
          else
            operands << parser.parse_object(token)
          end
        end
      end

      def reset_text_state
        @font = nil
        @font_size = 0.0
        @char_spacing = 0.0
        @word_spacing = 0.0
        @horiz_scale = 1.0
        @leading = 0.0
        @rise = 0.0
      end

      def execute(op, operands)
        case op
        when "q" then @ctm_stack.push(@ctm)
        when "Q" then @ctm = @ctm_stack.pop || RUDF::Matrix.identity
        when "cm" then @ctm = matrix_from(operands) * @ctm
        when "BT"
          @tm = RUDF::Matrix.identity
          @tlm = RUDF::Matrix.identity
        when "ET" then nil
        when "Tf" then set_font(operands)
        when "Td" then line_move(num(operands[0]), num(operands[1]))
        when "TD"
          @leading = -num(operands[1])
          line_move(num(operands[0]), num(operands[1]))
        when "Tm" then set_text_matrix(operands)
        when "T*" then line_move(0.0, -@leading)
        when "Tc" then @char_spacing = num(operands[0])
        when "Tw" then @word_spacing = num(operands[0])
        when "Tz" then @horiz_scale = num(operands[0]) / 100.0
        when "TL" then @leading = num(operands[0])
        when "Ts" then @rise = num(operands[0])
        when "Tj" then show_text(operands[0])
        when "TJ" then show_array(operands[0])
        when "'"
          line_move(0.0, -@leading)
          show_text(operands[0])
        when '"'
          @word_spacing = num(operands[0])
          @char_spacing = num(operands[1])
          line_move(0.0, -@leading)
          show_text(operands[2])
        end
      end

      def set_font(operands)
        name = operands[0]
        @font_size = num(operands[1])
        key = name.is_a?(Name) ? name.value : name.to_s
        @font = font_for(key)
      end

      def font_for(name)
        return @fonts[name] if @fonts.key?(name)

        fonts = res(@resources["Font"])
        dict = fonts.is_a?(Hash) ? res(fonts[name]) : nil
        @fonts[name] = dict.is_a?(Hash) ? Font.new(dict, @resolver) : nil
      end

      def set_text_matrix(operands)
        @tm = matrix_from(operands)
        @tlm = @tm
      end

      def line_move(tx, ty)
        @tlm = RUDF::Matrix.translate(tx, ty) * @tlm
        @tm = @tlm
      end

      def show_array(array)
        return unless array.is_a?(Array)

        array.each do |item|
          if item.is_a?(String)
            show_text(item)
          elsif item.is_a?(Numeric)
            # Positive numbers move left in text space (TJ kerning).
            tx = -item / 1000.0 * @font_size * @horiz_scale
            @tm = RUDF::Matrix.translate(tx, 0.0) * @tm
          end
        end
      end

      def show_text(str)
        return unless str.is_a?(String) && @font

        @font.decode(str).each do |code, text|
          w0 = @font.width(code)
          place_glyph(code, text, w0)
          advance = ((w0 * @font_size) + @char_spacing + (code == 32 ? @word_spacing : 0.0)) * @horiz_scale
          @tm = RUDF::Matrix.translate(advance, 0.0) * @tm
        end
      end

      # Compute the device-space bounding box of one glyph and record it.
      def place_glyph(_code, text, w0)
        trm = RUDF::Matrix.new(@font_size * @horiz_scale, 0.0, 0.0, @font_size, 0.0, @rise) * @tm * @ctm
        ascent = 0.8
        descent = -0.2
        p0 = RUDF::Point.new(0.0, descent).transform(trm)
        p1 = RUDF::Point.new(w0, ascent).transform(trm)
        origin = RUDF::Point.new(0.0, 0.0).transform(trm)

        xs = [p0.x, p1.x]
        ys = [p0.y, p1.y]
        @chars << Char.new(
          text: text,
          x0: xs.min, x1: xs.max,
          y0: flip(ys.max), y1: flip(ys.min),
          ox: origin.x, oy: flip(origin.y),
          font: font_name, size: @font_size
        )
      end

      def font_name
        "Font"
      end

      def flip(y)
        @page_height ? @page_height - y : y
      end

      # ---- grouping ----------------------------------------------------------

      def group_blocks(chars)
        return [] if chars.empty?

        lines = group_lines(chars)
        blocks = []
        current = []
        prev_bottom = nil
        lines.each do |line|
          top = line.map(&:y0).min
          height = line.map { |c| c.y1 - c.y0 }.max
          if prev_bottom && (top - prev_bottom) > height * 0.8
            blocks << current unless current.empty?
            current = []
          end
          current << line
          prev_bottom = line.map(&:y1).max
        end
        blocks << current unless current.empty?
        blocks
      end

      def group_lines(chars)
        sorted = chars.sort_by { |c| [c.oy.round(1), c.ox] }
        lines = []
        current = []
        baseline = nil
        sorted.each do |c|
          if baseline.nil? || (c.oy - baseline).abs <= [c.size * 0.5, 3.0].max
            current << c
            baseline ||= c.oy
          else
            lines << current.sort_by(&:ox)
            current = [c]
            baseline = c.oy
          end
        end
        lines << current.sort_by(&:ox) unless current.empty?
        lines
      end

      def line_text(line)
        out = +""
        prev = nil
        line.each do |c|
          if prev && needs_space?(prev, c)
            out << " " unless c.text == " " || out.end_with?(" ")
          end
          out << c.text
          prev = c
        end
        out.rstrip
      end

      def needs_space?(prev, c)
        gap = c.x0 - prev.x1
        gap > prev.size * 0.25
      end

      def split_words(line)
        words = []
        current = []
        prev = nil
        line.each do |c|
          if c.text.strip.empty?
            words << current unless current.empty?
            current = []
            prev = nil
            next
          end
          if prev && needs_space?(prev, c)
            words << current unless current.empty?
            current = []
          end
          current << c
          prev = c
        end
        words << current unless current.empty?
        words
      end

      def build_spans(line)
        spans = []
        current = nil
        line.each do |c|
          if current && current[:size] == c.size
            current[:text] << c.text
            current[:chars] << c
          else
            spans << finalize_span(current) if current
            current = { size: c.size, font: c.font, text: +c.text, chars: [c] }
          end
        end
        spans << finalize_span(current) if current
        spans
      end

      def finalize_span(span)
        {
          text: span[:text],
          font: span[:font],
          size: span[:size],
          bbox: union_bbox(span[:chars])
        }
      end

      def union_bbox(chars)
        return [0.0, 0.0, 0.0, 0.0] if chars.empty?

        [
          chars.map(&:x0).min,
          chars.map(&:y0).min,
          chars.map(&:x1).max,
          chars.map(&:y1).max
        ]
      end

      def res(value)
        value.is_a?(Reference) ? @resolver.call(value) : value
      end

      def matrix_from(operands)
        RUDF::Matrix.new(*operands.first(6).map { |v| num(v) })
      end

      def num(value)
        value.is_a?(Numeric) ? value.to_f : 0.0
      end
    end
  end
end
