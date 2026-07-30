# frozen_string_literal: true

module RUDF
  module PDF
    # A PDF name object, e.g. +/Type+. Stored without the leading slash.
    #
    # Names are value objects: two Name instances with the same string are
    # equal and hash alike, so they work as Hash keys.
    class Name
      attr_reader :value

      def initialize(value)
        @value = value.to_s
      end

      def ==(other)
        other.is_a?(Name) && other.value == @value
      end
      alias eql? ==

      def hash
        @value.hash
      end

      def to_sym
        @value.to_sym
      end

      def to_s
        "/#{@value}"
      end
      alias inspect to_s
    end

    # An indirect reference, e.g. +12 0 R+. Resolved lazily by the parser.
    Reference = Struct.new(:number, :generation) do
      def to_s
        "#{number} #{generation} R"
      end
      alias_method :inspect, :to_s
    end

    # A PDF stream object: a dictionary plus a byte payload.
    #
    # The +raw+ bytes are exactly as stored in the file; {#decoded} applies the
    # filters named in the dictionary (currently FlateDecode) on demand and
    # caches the result.
    class Stream
      attr_reader :dict, :raw

      def initialize(dict, raw, resolver = nil)
        @dict = dict
        @raw = raw
        @resolver = resolver
      end

      # The decoded stream contents, applying any supported filters.
      def decoded
        @decoded ||= Filters.apply(@dict, @raw, @resolver)
      end

      def to_s
        "Stream(#{@raw.bytesize} bytes, dict=#{@dict.inspect})"
      end
      alias inspect to_s
    end
  end
end
