# frozen_string_literal: true

require "zlib"

module RUDF
  module PDF
    # Decoders for PDF stream filters.
    #
    # Only the filters needed to read structural data and uncompressed content
    # are implemented. FlateDecode (with an optional PNG/TIFF predictor) covers
    # the overwhelming majority of real-world documents; unsupported filters
    # raise so callers can fall back gracefully.
    module Filters
      module_function

      # Decode +raw+ according to the +/Filter+ entry of +dict+, resolving any
      # indirect references through +resolver+ when provided.
      def apply(dict, raw, resolver = nil)
        filters = Array(fetch(dict, "Filter", resolver))
        params = normalize_params(fetch(dict, "DecodeParms", resolver) ||
                                  fetch(dict, "DP", resolver), filters.length)

        data = raw
        filters.each_with_index do |filter, i|
          name = filter.is_a?(Name) ? filter.value : filter.to_s
          data = decode(name, data, params[i], resolver)
        end
        data
      end

      def decode(name, data, parms, resolver)
        case name
        when "FlateDecode", "Fl"
          predictor(inflate(data), parms, resolver)
        when "ASCIIHexDecode", "AHx"
          ascii_hex(data)
        when "ASCII85Decode", "A85"
          ascii85(data)
        when nil, ""
          data
        else
          raise ParseError, "unsupported stream filter: #{name}"
        end
      end

      def inflate(data)
        Zlib::Inflate.inflate(data)
      rescue Zlib::Error
        # Some producers omit the zlib header or pad the stream; retry raw.
        begin
          zi = Zlib::Inflate.new(-Zlib::MAX_WBITS)
          out = zi.inflate(data)
          out << zi.finish if zi.respond_to?(:finish)
          zi.close
          out
        rescue Zlib::Error => e
          raise ParseError, "failed to inflate stream: #{e.message}"
        end
      end

      # Apply a PNG/TIFF predictor if requested by the DecodeParms.
      def predictor(data, parms, resolver)
        return data unless parms.is_a?(Hash)

        pred = int(fetch(parms, "Predictor", resolver))
        return data if pred.nil? || pred <= 1

        columns = int(fetch(parms, "Columns", resolver)) || 1
        colors = int(fetch(parms, "Colors", resolver)) || 1
        bpc = int(fetch(parms, "BitsPerComponent", resolver)) || 8
        bpp = [(colors * bpc / 8.0).ceil, 1].max
        row_len = (columns * colors * bpc / 8.0).ceil

        return data if pred < 10 # TIFF predictor 2 is rare; leave data as-is.

        png_predictor(data, row_len, bpp)
      end

      # Reverse a PNG predictor (predictor codes 10-15 use a per-row tag byte).
      def png_predictor(data, row_len, bpp)
        out = +""
        prev = Array.new(row_len, 0)
        pos = 0
        bytes = data.bytes
        while pos + 1 + row_len <= bytes.length + row_len && pos < bytes.length
          tag = bytes[pos]
          pos += 1
          row = bytes[pos, row_len] || []
          break if row.empty?

          pos += row_len
          decoded = Array.new(row.length, 0)
          row.each_index do |i|
            left = i >= bpp ? decoded[i - bpp] : 0
            up = prev[i] || 0
            up_left = i >= bpp ? (prev[i - bpp] || 0) : 0
            value = row[i]
            decoded[i] =
              case tag
              when 0 then value
              when 1 then value + left
              when 2 then value + up
              when 3 then value + ((left + up) / 2)
              when 4 then value + paeth(left, up, up_left)
              else value
              end & 0xff
          end
          out << decoded.pack("C*")
          prev = decoded
        end
        out
      end

      def paeth(a, b, c)
        p = a + b - c
        pa = (p - a).abs
        pb = (p - b).abs
        pc = (p - c).abs
        if pa <= pb && pa <= pc
          a
        elsif pb <= pc
          b
        else
          c
        end
      end

      def ascii_hex(data)
        hex = data.delete("^0-9A-Fa-f>")
        hex = hex[0...hex.index(">")] if hex.include?(">")
        hex = "#{hex}0" if hex.length.odd?
        [hex].pack("H*")
      end

      def ascii85(data)
        data = data.sub(/^<~/, "").sub(/~>.*$/m, "")
        out = +""
        group = []
        data.each_char do |ch|
          next if ch =~ /\s/

          if ch == "z" && group.empty?
            out << "\0\0\0\0"
            next
          end
          group << (ch.ord - 33)
          next unless group.length == 5

          out << decode_ascii85_group(group, 4)
          group = []
        end
        unless group.empty?
          n = group.length
          group.fill(84, n...5)
          out << decode_ascii85_group(group, n - 1)
        end
        out
      end

      def decode_ascii85_group(group, count)
        value = group.inject(0) { |acc, c| (acc * 85) + c }
        bytes = [(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]
        bytes[0, count].pack("C*")
      end

      def normalize_params(parms, count)
        return Array.new(count) if parms.nil?

        parms.is_a?(Array) ? parms : [parms]
      end

      def fetch(dict, key, resolver)
        return nil unless dict.is_a?(Hash)

        value = dict[key] || dict[Name.new(key)]
        resolve(value, resolver)
      end

      def resolve(value, resolver)
        return value unless value.is_a?(Reference) && resolver

        resolver.call(value)
      end

      def int(value)
        return nil if value.nil?

        value.to_i
      end
    end
  end
end
