# frozen_string_literal: true

require_relative "lexer"
require_relative "object"

module RUDF
  module PDF
    # Recursive-descent parser for individual PDF objects.
    #
    # Given a {Lexer} positioned at the start of an object, {#parse_object}
    # returns the corresponding Ruby value: Integer/Float for numbers, String
    # for strings, +true+/+false+/+nil+ for keywords, {Name} for names, Array
    # for arrays, Hash for dictionaries, {Reference} for +N G R+ and {Stream}
    # for stream objects.
    class Parser
      def initialize(data, lexer: nil, resolver: nil, decryptor: nil)
        @data = data
        @lexer = lexer || Lexer.new(data)
        @resolver = resolver
        @decryptor = decryptor
        @obj_num = nil
        @obj_gen = nil
      end

      attr_reader :lexer

      # Parse the +N G obj ... endobj+ found at +offset+ and return its value.
      def parse_indirect_object(offset)
        @lexer = Lexer.new(@data, offset)
        num = @lexer.next_token
        gen = @lexer.next_token
        obj = @lexer.next_token
        unless num.type == :number && gen.type == :number &&
               obj.type == :keyword && obj.value == "obj"
          raise ParseError, "expected 'N G obj' at offset #{offset}"
        end

        # Remember the object identity so any strings/streams inside it can be
        # decrypted with the correct per-object key.
        @obj_num = num.value
        @obj_gen = gen.value
        parse_object
      end

      # Parse a single object starting at the lexer's current position.
      def parse_object(token = nil)
        token ||= @lexer.next_token
        case token.type
        when :number
          parse_number_or_reference(token)
        when :string
          decrypt_string(token.value)
        when :boolean, :null, :name
          token.value
        when :array_open
          parse_array
        when :dict_open
          parse_dictionary
        when :keyword
          # Bare keyword in object position (e.g. within content). Return it
          # verbatim so higher layers can interpret operators.
          Keyword.new(token.value)
        when :eof
          nil
        else
          raise ParseError, "unexpected token #{token.type} (#{token.value.inspect})"
        end
      end

      # Wrapper for content-stream operators and stray keywords.
      Keyword = Struct.new(:name) do
        def to_s
          name
        end
      end

      private

      def parse_number_or_reference(first)
        return first.value unless first.value.is_a?(Integer)

        # Look ahead for an indirect reference "G R".
        save = @lexer.pos
        second = @lexer.next_token
        if second.type == :number && second.value.is_a?(Integer)
          third = @lexer.next_token
          if third.type == :keyword && third.value == "R"
            return Reference.new(first.value, second.value)
          end
        end
        @lexer.pos = save
        first.value
      end

      def parse_array
        result = []
        loop do
          token = @lexer.next_token
          break if token.type == :array_close || token.type == :eof

          result << parse_object(token)
        end
        result
      end

      def parse_dictionary
        dict = {}
        loop do
          key_token = @lexer.next_token
          break if key_token.type == :dict_close || key_token.type == :eof

          raise ParseError, "dictionary key must be a name" unless key_token.type == :name

          key = key_token.value.value
          dict[key] = parse_object
        end

        # A dictionary immediately followed by the `stream` keyword is a stream.
        save = @lexer.pos
        nxt = @lexer.next_token
        if nxt.type == :keyword && nxt.value == "stream"
          build_stream(dict)
        else
          @lexer.pos = save
          dict
        end
      end

      def build_stream(dict)
        start = @lexer.stream_data_start
        length = resolved_length(dict["Length"])
        raw =
          if length && start + length <= @data.bytesize
            candidate = @data.byteslice(start, length)
            # Verify the declared length lands on an endstream marker; if not,
            # fall back to scanning so we tolerate wrong /Length values.
            verify_endstream(start + length) ? candidate : scan_stream(start)
          else
            scan_stream(start)
          end
        raw = decrypt_stream(raw)
        Stream.new(dict, raw, @resolver)
      end

      def decrypt_string(value)
        return value unless @decryptor && @obj_num

        @decryptor.call(value, @obj_num, @obj_gen, :string)
      end

      def decrypt_stream(raw)
        return raw unless @decryptor && @obj_num

        @decryptor.call(raw, @obj_num, @obj_gen, :stream)
      end

      def resolved_length(value)
        value = @resolver.call(value) if value.is_a?(Reference) && @resolver
        value.is_a?(Integer) ? value : nil
      end

      def verify_endstream(pos)
        window = @data.byteslice(pos, 20).to_s
        window.lstrip.start_with?("endstream")
      end

      def scan_stream(start)
        idx = @data.index("endstream", start)
        return @data.byteslice(start..-1).to_s if idx.nil?

        finish = idx
        # Trim the single EOL that precedes `endstream`.
        finish -= 1 if finish > start && @data.getbyte(finish - 1) == 0x0A
        finish -= 1 if finish > start && @data.getbyte(finish - 1) == 0x0D
        @data.byteslice(start, finish - start).to_s
      end
    end
  end
end
