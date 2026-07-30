# frozen_string_literal: true

require_relative "lexer"

module RUDF
  module PDF
    # A parsed +/ToUnicode+ CMap: a mapping from character codes to Unicode
    # strings.
    #
    # It understands the +begincodespacerange+, +beginbfchar+ and
    # +beginbfrange+ sections of a CMap stream. Character codes may be one or
    # two bytes wide; the code-space range determines the width so that
    # variable-length decoding of a showable string works correctly.
    class CMap
      def initialize
        @single = {}          # code (Integer) => String
        @ranges = []          # [lo, hi, base_string_or_array]
        @code_bytes = 1
      end

      attr_reader :code_bytes

      # Parse a CMap from its (already decoded) byte string.
      def self.parse(data)
        cmap = new
        cmap.send(:load, data)
        cmap
      end

      # Split +bytes+ into character codes using the code-space width, then map
      # each to its Unicode string. Unmapped codes yield the Unicode
      # replacement character so extraction never loses positional alignment.
      def decode(bytes)
        out = +""
        each_code(bytes) { |code| out << (lookup(code) || "�") }
        out
      end

      # Yield each integer character code found in +bytes+.
      def each_code(bytes)
        b = bytes.b
        i = 0
        step = @code_bytes
        while i < b.bytesize
          code = 0
          step.times do |k|
            code = (code << 8) | (b.getbyte(i + k) || 0)
          end
          yield code
          i += step
        end
      end

      def lookup(code)
        return @single[code] if @single.key?(code)

        @ranges.each do |lo, hi, base|
          next unless code >= lo && code <= hi

          if base.is_a?(Array)
            idx = code - lo
            return base[idx] if idx < base.length
          else
            # Increment the last code unit of the base string by the offset.
            return offset_string(base, code - lo)
          end
        end
        nil
      end

      private

      def load(data)
        lexer = Lexer.new(data)
        stack = []
        loop do
          token = lexer.next_token
          break if token.type == :eof

          case token.type
          when :keyword
            handle_keyword(token.value, stack, lexer)
            stack = []
          else
            stack << token
          end
        end
      end

      def handle_keyword(word, stack, lexer)
        case word
        when "begincodespacerange"
          read_codespace(lexer)
        when "beginbfchar"
          read_bfchar(lexer)
        when "beginbfrange"
          read_bfrange(lexer)
        end
      end

      def read_codespace(lexer)
        loop do
          tok = lexer.next_token
          break if tok.type == :eof || (tok.type == :keyword && tok.value == "endcodespacerange")
          next unless tok.type == :string

          @code_bytes = [@code_bytes, tok.value.bytesize].max
          lexer.next_token # the high end of the range
        end
      end

      def read_bfchar(lexer)
        loop do
          src = lexer.next_token
          break if src.type == :eof || (src.type == :keyword && src.value == "endbfchar")
          next unless src.type == :string

          dst = lexer.next_token
          code = bytes_to_int(src.value)
          @code_bytes = [@code_bytes, src.value.bytesize].max
          @single[code] = utf16_to_utf8(dst.value) if dst.type == :string
        end
      end

      def read_bfrange(lexer)
        loop do
          lo_tok = lexer.next_token
          break if lo_tok.type == :eof || (lo_tok.type == :keyword && lo_tok.value == "endbfrange")
          next unless lo_tok.type == :string

          hi_tok = lexer.next_token
          dst_tok = lexer.next_token
          lo = bytes_to_int(lo_tok.value)
          hi = bytes_to_int(hi_tok.value)
          @code_bytes = [@code_bytes, lo_tok.value.bytesize].max

          if dst_tok.type == :array_open
            list = read_string_array(lexer)
            @ranges << [lo, hi, list]
          elsif dst_tok.type == :string
            @ranges << [lo, hi, utf16_to_utf8(dst_tok.value)]
          end
        end
      end

      def read_string_array(lexer)
        list = []
        loop do
          tok = lexer.next_token
          break if tok.type == :array_close || tok.type == :eof

          list << utf16_to_utf8(tok.value) if tok.type == :string
        end
        list
      end

      def bytes_to_int(str)
        str.b.each_byte.inject(0) { |acc, byte| (acc << 8) | byte }
      end

      def utf16_to_utf8(str)
        b = str.b
        # ToUnicode destination strings are UTF-16BE (possibly multiple units).
        if b.bytesize.even? && b.bytesize >= 2
          b.force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        else
          b.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
        end
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        "�"
      end

      def offset_string(base, offset)
        return base if offset.zero?

        codepoints = base.codepoints
        return base if codepoints.empty?

        codepoints[-1] += offset
        codepoints.pack("U*")
      rescue RangeError
        base
      end
    end
  end
end
