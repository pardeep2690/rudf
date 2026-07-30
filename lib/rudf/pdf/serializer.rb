# frozen_string_literal: true

module RUDF
  module PDF
    # Serializes parsed PDF values back into PDF syntax.
    #
    # Used by in-place editing to re-emit a modified object (for example a page
    # dictionary with an extra content stream and font resource) as part of an
    # incremental update. References are preserved so the appended object still
    # points at the document's existing objects.
    module Serializer
      module_function

      def serialize(value)
        case value
        when Name then value.to_s
        when Reference then "#{value.number} #{value.generation} R"
        when Integer then value.to_s
        when Float then format_float(value)
        when true then "true"
        when false then "false"
        when nil then "null"
        when String then serialize_string(value)
        when Array then "[ #{value.map { |v| serialize(v) }.join(' ')} ]"
        when Hash then serialize_dict(value)
        else
          raise ParseError, "cannot serialize #{value.class}"
        end
      end

      def serialize_dict(hash)
        body = hash.map { |key, val| "/#{key} #{serialize(val)}" }.join(" ")
        "<< #{body} >>"
      end

      # Emit as a literal string when it is printable ASCII, otherwise as a hex
      # string so binary data survives round-tripping.
      def serialize_string(str)
        bytes = str.b
        if bytes.each_byte.all? { |b| b >= 0x20 && b < 0x7F }
          escaped = bytes.gsub("\\", "\\\\\\\\").gsub("(", "\\(").gsub(")", "\\)")
          "(#{escaped})"
        else
          "<#{bytes.unpack1('H*')}>"
        end
      end

      def format_float(value)
        return value.to_i.to_s if value == value.to_i

        format("%.6f", value).sub(/0+\z/, "").sub(/\.\z/, "")
      end
    end
  end
end
