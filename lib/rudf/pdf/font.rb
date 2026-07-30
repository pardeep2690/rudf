# frozen_string_literal: true

require_relative "cmap"
require_relative "glyph_list"

module RUDF
  module PDF
    # A page font resource, wrapping a PDF font dictionary.
    #
    # It knows how to turn a shown byte string into Unicode text and how wide
    # each character advances, which the text-extraction engine needs both to
    # produce readable output and to place glyph bounding boxes.
    #
    # Decoding precedence, matching what real viewers do:
    #   1. +/ToUnicode+ CMap, when present (most reliable).
    #   2. +/Encoding+ base encoding + +/Differences+ (simple fonts).
    #   3. Latin-1 fallback.
    class Font
      DEFAULT_WIDTH = 500 # glyph-space units (1000 per em)

      def initialize(dict, resolver)
        @dict = dict || {}
        @resolver = resolver
        @to_unicode = build_to_unicode
        @composite = composite?
        @differences = build_differences
        @base_encoding = base_encoding_name
        build_widths
      end

      # True for Type0 (multi-byte) fonts.
      def composite?
        subtype = res(@dict["Subtype"])
        subtype.is_a?(Name) && subtype.value == "Type0"
      end

      # Decode a shown string into an array of +[code, text]+ pairs, preserving
      # per-code granularity so the caller can advance the text cursor.
      def decode(bytes)
        pairs = []
        each_code(bytes) do |code|
          pairs << [code, code_to_text(code)]
        end
        pairs
      end

      # Decoded Unicode text of a whole shown string.
      def to_text(bytes)
        decode(bytes).map(&:last).join
      end

      # Advance width of +code+ in text-space units (glyph units / 1000).
      def width(code)
        (@widths[code] || @default_width).to_f / 1000.0
      end

      # Iterate integer character codes in +bytes+ (1 or 2 bytes each).
      def each_code(bytes, &block)
        if @composite
          # Composite fonts here assume a 2-byte encoding (Identity-H is by far
          # the most common); honour the ToUnicode code width if it disagrees.
          step = @to_unicode&.code_bytes == 1 ? 1 : 2
          b = bytes.b
          i = 0
          while i < b.bytesize
            code = 0
            step.times { |k| code = (code << 8) | (b.getbyte(i + k) || 0) }
            block.call(code)
            i += step
          end
        else
          bytes.b.each_byte(&block)
        end
      end

      private

      def res(value)
        value.is_a?(Reference) ? @resolver.call(value) : value
      end

      def code_to_text(code)
        if @to_unicode
          mapped = @to_unicode.lookup(code)
          return mapped if mapped
        end
        return simple_char(code) unless @composite

        # No ToUnicode for a composite font: nothing reliable to show.
        "�"
      end

      def simple_char(code)
        # A /Differences override wins.
        if (name = @differences[code])
          ch = GlyphList.to_char(name)
          return ch if ch
        end
        decode_base(code)
      end

      def decode_base(code)
        enc =
          case @base_encoding
          when "WinAnsiEncoding" then Encoding::Windows_1252
          when "MacRomanEncoding" then Encoding::MacRoman
          else Encoding::ISO_8859_1
          end
        [code].pack("C").force_encoding(enc).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        [code].pack("C").force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
      end

      def build_to_unicode
        stream = res(@dict["ToUnicode"])
        return nil unless stream.is_a?(Stream)

        CMap.parse(stream.decoded)
      rescue ParseError
        nil
      end

      def base_encoding_name
        enc = res(@dict["Encoding"])
        case enc
        when Name then enc.value
        when Hash
          base = res(enc["BaseEncoding"])
          base.is_a?(Name) ? base.value : "StandardEncoding"
        else
          "StandardEncoding"
        end
      end

      def build_differences
        enc = res(@dict["Encoding"])
        return {} unless enc.is_a?(Hash)

        diffs = res(enc["Differences"])
        return {} unless diffs.is_a?(Array)

        table = {}
        current = 0
        diffs.each do |item|
          item = res(item)
          if item.is_a?(Integer)
            current = item
          elsif item.is_a?(Name)
            table[current] = item.value
            current += 1
          end
        end
        table
      end

      def build_widths
        @widths = {}
        @default_width = DEFAULT_WIDTH
        if @composite
          build_composite_widths
        else
          build_simple_widths
        end
      end

      def build_simple_widths
        first = res(@dict["FirstChar"])
        arr = res(@dict["Widths"])
        return unless first.is_a?(Integer) && arr.is_a?(Array)

        arr.each_with_index do |w, i|
          w = res(w)
          @widths[first + i] = w if w.is_a?(Numeric)
        end
      end

      def build_composite_widths
        descendants = res(@dict["DescendantFonts"])
        cid_font = descendants.is_a?(Array) ? res(descendants.first) : nil
        return unless cid_font.is_a?(Hash)

        dw = res(cid_font["DW"])
        @default_width = dw if dw.is_a?(Numeric)

        w = res(cid_font["W"])
        parse_cid_widths(w) if w.is_a?(Array)
      end

      # The composite /W array is a sequence of either
      #   c [w1 w2 ...]        (codes c, c+1, ... get w1, w2, ...)
      # or
      #   c_first c_last w     (codes c_first..c_last all get w)
      def parse_cid_widths(arr)
        i = 0
        while i < arr.length
          first = res(arr[i])
          nxt = res(arr[i + 1])
          if nxt.is_a?(Array)
            nxt.each_with_index { |w, k| @widths[first + k] = res(w) }
            i += 2
          elsif nxt.is_a?(Numeric)
            last = nxt.to_i
            w = res(arr[i + 2])
            (first..last).each { |c| @widths[c] = w }
            i += 3
          else
            break
          end
        end
      end
    end
  end
end
