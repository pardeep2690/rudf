# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"

module RUDF
  module PDF
    # A minimal content-stream interpreter that extracts visible text.
    #
    # It tokenizes a page's content stream and tracks the text-showing
    # operators (+Tj+, +TJ+, +'+, +"+) together with the line/positioning
    # operators (+Td+, +TD+, +T*+, +Tm+) so that extracted text keeps a
    # reasonable amount of the original line structure. Font decoding is not
    # performed: bytes are interpreted as Latin-1/PDFDoc text, which is correct
    # for the common case of standard fonts with simple encodings.
    class ContentStream
      def initialize(data)
        @data = data
      end

      # Return the page text as a String, inserting newlines where the text
      # cursor moves down the page.
      def text
        pieces = []
        operands = []
        lexer = Lexer.new(@data)
        parser = Parser.new(@data, lexer: lexer)

        loop do
          token = lexer.next_token
          break if token.type == :eof

          case token.type
          when :keyword
            handle_operator(token.value, operands, pieces)
            operands = []
          when :array_open
            operands << parser.parse_object(token)
          when :dict_open
            operands << parser.parse_object(token)
          else
            operands << parser.parse_object(token)
          end
        end

        normalize(pieces.join)
      end

      private

      def handle_operator(op, operands, pieces)
        case op
        when "Tj"
          str = operands.last
          pieces << decode(str) if str.is_a?(String)
        when "'"
          pieces << "\n"
          str = operands.last
          pieces << decode(str) if str.is_a?(String)
        when '"'
          pieces << "\n"
          str = operands.last
          pieces << decode(str) if str.is_a?(String)
        when "TJ"
          array = operands.last
          pieces << decode_tj_array(array) if array.is_a?(Array)
        when "Td", "TD", "T*"
          pieces << "\n"
        when "ET"
          pieces << "\n"
        end
      end

      # A TJ array interleaves strings with kerning numbers; large negative
      # adjustments imply an inter-word space.
      def decode_tj_array(array)
        out = +""
        array.each do |item|
          if item.is_a?(String)
            out << decode(item)
          elsif item.is_a?(Numeric) && item < -100
            out << " "
          end
        end
        out
      end

      def decode(str)
        str.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        str
      end

      def normalize(text)
        text.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
      end
    end
  end
end
