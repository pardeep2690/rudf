# frozen_string_literal: true

require "zlib"

module RUDF
  module PDF
    # A minimal PNG encoder shared by image extraction and page rendering.
    #
    # It writes a single-image PNG with filter type 0 (None) on every row.
    # Callers supply already-laid-out sample bytes plus the PNG colour type and
    # bit depth; no colour conversion happens here.
    module PNG
      COLOR_GRAY = 0
      COLOR_RGB = 2
      COLOR_INDEXED = 3
      COLOR_GRAY_ALPHA = 4
      COLOR_RGBA = 6

      CHANNELS = {
        COLOR_GRAY => 1, COLOR_RGB => 3, COLOR_INDEXED => 1,
        COLOR_GRAY_ALPHA => 2, COLOR_RGBA => 4
      }.freeze

      module_function

      # Encode +data+ (raw samples, row-major, no filter bytes) into PNG bytes.
      def encode(width, height, data, color_type: COLOR_RGB, bit_depth: 8)
        channels = CHANNELS.fetch(color_type)
        row_bytes = ((width * channels * bit_depth) + 7) / 8
        raw = +"".b
        height.times do |y|
          raw << "\x00".b
          raw << (data.byteslice(y * row_bytes, row_bytes) || ("\x00".b * row_bytes))
        end

        out = +"\x89PNG\r\n\x1A\n".b
        out << chunk("IHDR", [width, height].pack("N2") + [bit_depth, color_type, 0, 0, 0].pack("C5"))
        out << chunk("IDAT", Zlib::Deflate.deflate(raw))
        out << chunk("IEND", "".b)
        out
      end

      def chunk(type, data)
        body = type.b + data.b
        [data.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
      end
    end
  end
end
