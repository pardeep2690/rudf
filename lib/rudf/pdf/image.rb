# frozen_string_literal: true

require "zlib"

module RUDF
  module PDF
    # Reads an image XObject and produces a usable image file.
    #
    # JPEG (+DCTDecode+) and JPEG 2000 (+JPXDecode+) payloads are already
    # complete image files and are returned verbatim. Everything else is
    # decoded to raw samples and wrapped into a PNG, converting CMYK and
    # indexed colour to RGB along the way. This mirrors the intent of
    # +fitz.Document.extract_image+: hand back bytes a viewer can open.
    class Image
      attr_reader :width, :height, :bpc, :colorspace_name, :filter_name

      def initialize(stream, resolver)
        @stream = stream
        @resolver = resolver
        @dict = stream.dict
        @width = int(@dict["Width"] || @dict["W"]) || 0
        @height = int(@dict["Height"] || @dict["H"]) || 0
        @bpc = int(@dict["BitsPerComponent"] || @dict["BPC"]) || 8
        @filter_name = last_filter
        @colorspace_name = colorspace_label
      end

      # Metadata tuple used by +Page#get_images+ style listings.
      def info
        {
          width: @width,
          height: @height,
          bpc: @bpc,
          colorspace: @colorspace_name,
          filter: @filter_name
        }
      end

      # Return +{ ext:, image:, width:, height:, colorspace:, bpc: }+ where
      # +image+ is the raw bytes of a standalone image file.
      def extract
        base = { width: @width, height: @height, colorspace: @colorspace_name, bpc: @bpc }
        case @filter_name
        when "DCTDecode" then base.merge(ext: "jpg", image: @stream.raw)
        when "JPXDecode" then base.merge(ext: "jp2", image: @stream.raw)
        else base.merge(ext: "png", image: to_png)
        end
      end

      private

      # ---- colour model ------------------------------------------------------

      def colorspace_label
        cs = res(@dict["ColorSpace"] || @dict["CS"])
        case cs
        when Name then normalize_cs_name(cs.value)
        when Array then array_cs_label(cs)
        else "DeviceGray"
        end
      end

      def normalize_cs_name(name)
        case name
        when "G", "DeviceGray", "CalGray" then "DeviceGray"
        when "RGB", "DeviceRGB", "CalRGB" then "DeviceRGB"
        when "CMYK", "DeviceCMYK" then "DeviceCMYK"
        when "I", "Indexed" then "Indexed"
        else name
        end
      end

      def array_cs_label(arr)
        head = res(arr[0])
        name = head.is_a?(Name) ? head.value : head.to_s
        case name
        when "ICCBased"
          n = int(res(res(arr[1])&.dict&.fetch("N", nil))) || 3
          { 1 => "DeviceGray", 3 => "DeviceRGB", 4 => "DeviceCMYK" }[n] || "DeviceRGB"
        when "Indexed", "I" then "Indexed"
        when "CalRGB", "Lab" then "DeviceRGB"
        when "CalGray" then "DeviceGray"
        else name
        end
      end

      def channels_for(label)
        case label
        when "DeviceGray" then 1
        when "DeviceRGB" then 3
        when "DeviceCMYK" then 4
        when "Indexed" then 1
        else 3
        end
      end

      # ---- PNG construction --------------------------------------------------

      def to_png
        samples = @stream.decoded
        label = @colorspace_name

        if label == "Indexed"
          rgb = expand_indexed(samples)
          write_png(@width, @height, 2, 8, rgb)
        elsif label == "DeviceCMYK"
          rgb = cmyk_to_rgb(samples)
          write_png(@width, @height, 2, 8, rgb)
        elsif label == "DeviceRGB"
          write_png(@width, @height, 2, @bpc, samples)
        else # DeviceGray (or unknown single-channel)
          write_png(@width, @height, 0, @bpc, samples)
        end
      rescue ParseError, Zlib::Error
        # Unsupported compression (e.g. CCITT/LZW) — hand back raw payload.
        @stream.raw
      end

      def expand_indexed(samples)
        cs = res(@dict["ColorSpace"] || @dict["CS"])
        base_label, lookup = indexed_palette(cs)
        base_channels = channels_for(base_label)
        out = +"".b
        bytes = samples.bytes
        pixel_count = @width * @height
        pixel_count.times do |i|
          idx = bytes[i] || 0
          entry = lookup.byteslice(idx * base_channels, base_channels) || ("\x00".b * base_channels)
          out << palette_entry_to_rgb(entry, base_label)
        end
        out
      end

      def indexed_palette(cs)
        return ["DeviceRGB", "".b] unless cs.is_a?(Array) && cs.length >= 4

        base = res(cs[1])
        base_label = base.is_a?(Name) ? normalize_cs_name(base.value) : array_cs_label(Array(base))
        lookup = res(cs[3])
        table = lookup.is_a?(Stream) ? lookup.decoded : (lookup.is_a?(String) ? lookup.b : "".b)
        [base_label, table]
      end

      def palette_entry_to_rgb(entry, base_label)
        bytes = entry.bytes
        case base_label
        when "DeviceGray" then (bytes[0] || 0).chr * 3
        when "DeviceCMYK" then cmyk_pixel_to_rgb(*bytes.first(4))
        else # DeviceRGB
          [(bytes[0] || 0), (bytes[1] || 0), (bytes[2] || 0)].pack("C3")
        end
      end

      def cmyk_to_rgb(samples)
        out = +"".b
        bytes = samples.bytes
        (bytes.length / 4).times do |i|
          c, m, y, k = bytes[i * 4, 4]
          out << cmyk_pixel_to_rgb(c, m, y, k)
        end
        out
      end

      def cmyk_pixel_to_rgb(c, m, y, k)
        c ||= 0
        m ||= 0
        y ||= 0
        k ||= 0
        r = (255 - c) * (255 - k) / 255
        g = (255 - m) * (255 - k) / 255
        b = (255 - y) * (255 - k) / 255
        [r, g, b].pack("C3")
      end

      def write_png(width, height, color_type, bit_depth, pixel_data)
        row_bytes = row_length(width, color_type, bit_depth)
        raw = +"".b
        height.times do |y|
          raw << "\x00".b # filter type 0 (None)
          raw << (pixel_data.byteslice(y * row_bytes, row_bytes) || ("\x00".b * row_bytes))
        end

        out = +"\x89PNG\r\n\x1A\n".b
        out << png_chunk("IHDR", [width, height].pack("N2") + [bit_depth, color_type, 0, 0, 0].pack("C5"))
        out << png_chunk("IDAT", Zlib::Deflate.deflate(raw))
        out << png_chunk("IEND", "".b)
        out
      end

      def row_length(width, color_type, bit_depth)
        channels = color_type == 2 ? 3 : 1
        ((width * channels * bit_depth) + 7) / 8
      end

      def png_chunk(type, data)
        body = type.b + data.b
        [data.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
      end

      # ---- helpers -----------------------------------------------------------

      def last_filter
        filters = Array(res(@dict["Filter"] || @dict["F"]))
        name = filters.last
        name.is_a?(Name) ? name.value : name&.to_s
      end

      def res(value)
        value.is_a?(Reference) ? @resolver.call(value) : value
      end

      def int(value)
        value = res(value)
        value.is_a?(Numeric) ? value.to_i : nil
      end
    end
  end
end
