# frozen_string_literal: true

module RUDF
  module PDF
    # A tokenizer for PDF object syntax.
    #
    # The lexer walks a byte string and yields {Token} structs. It handles the
    # full set of PDF token kinds needed by the parser: numbers, literal and
    # hexadecimal strings, names, delimiters for arrays and dictionaries, and
    # bare keywords such as +obj+, +stream+, +R+, +true+ and +null+.
    class Lexer
      WHITESPACE = "\x00\t\n\f\r ".bytes.freeze
      DELIMITERS = "()<>[]{}/%".bytes.freeze

      Token = Struct.new(:type, :value)

      attr_reader :pos

      def initialize(data, pos = 0)
        @data = data
        @pos = pos
        @len = data.bytesize
      end

      def pos=(value)
        @pos = value
      end

      def eof?
        @pos >= @len
      end

      # Return the next token, or a +:eof+ token at end of input.
      def next_token
        skip_whitespace_and_comments
        return Token.new(:eof, nil) if eof?

        ch = byte(@pos)
        case ch
        when 0x2F # /
          read_name
        when 0x28 # (
          read_literal_string
        when 0x3C # <
          if byte(@pos + 1) == 0x3C
            @pos += 2
            Token.new(:dict_open, "<<")
          else
            read_hex_string
          end
        when 0x3E # >
          if byte(@pos + 1) == 0x3E
            @pos += 2
            Token.new(:dict_close, ">>")
          else
            @pos += 1
            Token.new(:error, ">")
          end
        when 0x5B # [
          @pos += 1
          Token.new(:array_open, "[")
        when 0x5D # ]
          @pos += 1
          Token.new(:array_close, "]")
        when 0x7B # {
          @pos += 1
          Token.new(:brace_open, "{")
        when 0x7D # }
          @pos += 1
          Token.new(:brace_close, "}")
        else
          if number_start?(ch)
            read_number
          else
            read_keyword
          end
        end
      end

      # Advance past the +stream+ keyword's trailing EOL and return the byte
      # offset at which the stream payload begins.
      def stream_data_start
        # Called immediately after a `stream` keyword token was read.
        if byte(@pos) == 0x0D # CR
          @pos += 1
          @pos += 1 if byte(@pos) == 0x0A
        elsif byte(@pos) == 0x0A # LF
          @pos += 1
        end
        @pos
      end

      private

      def byte(index)
        return nil if index.nil? || index < 0 || index >= @len

        @data.getbyte(index)
      end

      def skip_whitespace_and_comments
        loop do
          ch = byte(@pos)
          if ch.nil?
            break
          elsif WHITESPACE.include?(ch)
            @pos += 1
          elsif ch == 0x25 # % comment to end of line
            @pos += 1
            @pos += 1 while (c = byte(@pos)) && c != 0x0A && c != 0x0D
          else
            break
          end
        end
      end

      def number_start?(ch)
        (ch >= 0x30 && ch <= 0x39) || ch == 0x2B || ch == 0x2D || ch == 0x2E
      end

      def delimiter_or_ws?(ch)
        ch.nil? || WHITESPACE.include?(ch) || DELIMITERS.include?(ch)
      end

      def read_number
        start = @pos
        @pos += 1 if [0x2B, 0x2D].include?(byte(@pos))
        seen_dot = false
        while (ch = byte(@pos))
          if ch >= 0x30 && ch <= 0x39
            @pos += 1
          elsif ch == 0x2E && !seen_dot
            seen_dot = true
            @pos += 1
          else
            break
          end
        end
        text = @data.byteslice(start, @pos - start)
        value = seen_dot ? text.to_f : text.to_i
        Token.new(:number, value)
      end

      def read_name
        @pos += 1 # skip /
        start = @pos
        buffer = +""
        while (ch = byte(@pos))
          break if delimiter_or_ws?(ch)

          if ch == 0x23 && byte(@pos + 1) && byte(@pos + 2) # #xx escape
            hex = @data.byteslice(@pos + 1, 2)
            buffer << hex.to_i(16).chr
            @pos += 3
          else
            buffer << ch.chr
            @pos += 1
          end
        end
        buffer = @data.byteslice(start, @pos - start) if buffer.empty? && @pos > start
        Token.new(:name, Name.new(buffer))
      end

      def read_literal_string
        @pos += 1 # skip (
        depth = 1
        buffer = +""
        while (ch = byte(@pos))
          case ch
          when 0x5C # backslash escape
            @pos += 1
            buffer << read_escape
          when 0x28 # (
            depth += 1
            buffer << "("
            @pos += 1
          when 0x29 # )
            depth -= 1
            @pos += 1
            break if depth.zero?

            buffer << ")"
          else
            buffer << ch.chr
            @pos += 1
          end
        end
        Token.new(:string, buffer)
      end

      def read_escape
        ch = byte(@pos)
        case ch
        when 0x6E then @pos += 1; "\n"
        when 0x72 then @pos += 1; "\r"
        when 0x74 then @pos += 1; "\t"
        when 0x62 then @pos += 1; "\b"
        when 0x66 then @pos += 1; "\f"
        when 0x28 then @pos += 1; "("
        when 0x29 then @pos += 1; ")"
        when 0x5C then @pos += 1; "\\"
        when 0x0A then @pos += 1; "" # line continuation
        when 0x0D
          @pos += 1
          @pos += 1 if byte(@pos) == 0x0A
          ""
        when 0x30..0x37 # up to three octal digits
          oct = +""
          3.times do
            c = byte(@pos)
            break unless c && c >= 0x30 && c <= 0x37

            oct << c.chr
            @pos += 1
          end
          (oct.to_i(8) & 0xff).chr
        else
          @pos += 1
          ch.chr
        end
      end

      def read_hex_string
        @pos += 1 # skip <
        hex = +""
        while (ch = byte(@pos))
          break if ch == 0x3E # >

          hex << ch.chr unless WHITESPACE.include?(ch)
          @pos += 1
        end
        @pos += 1 # skip >
        hex = "#{hex}0" if hex.length.odd?
        Token.new(:string, [hex].pack("H*"))
      end

      def read_keyword
        start = @pos
        @pos += 1 while (ch = byte(@pos)) && !delimiter_or_ws?(ch)
        word = @data.byteslice(start, @pos - start)
        case word
        when "true" then Token.new(:boolean, true)
        when "false" then Token.new(:boolean, false)
        when "null" then Token.new(:null, nil)
        else Token.new(:keyword, word)
        end
      end
    end
  end
end
