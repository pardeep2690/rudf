# frozen_string_literal: true

require_relative "pdf/png"

module RUDF
  # A rendered raster image of a page, analogous to +fitz.Pixmap+.
  #
  # A Pixmap holds interleaved sample bytes with +n+ components per pixel
  # (1 = gray, 2 = gray+alpha, 3 = RGB, 4 = RGBA). It can report individual
  # pixels and serialise itself to PNG. Instances are produced by
  # {Page#get_pixmap} through a native backend, but the class is pure Ruby and
  # can be constructed directly from samples.
  class Pixmap
    attr_reader :width, :height, :n, :samples, :xres, :yres

    def initialize(width:, height:, n:, samples:, xres: 96, yres: 96)
      @width = width
      @height = height
      @n = n
      @samples = samples.b
      @xres = xres
      @yres = yres
    end

    # Bytes per row.
    def stride
      @width * @n
    end

    def alpha?
      @n == 2 || @n == 4
    end

    # A short colorspace label inferred from the component count.
    def colorspace
      case @n
      when 1, 2 then "DeviceGray"
      else "DeviceRGB"
      end
    end

    # The +n+ component bytes of the pixel at (+x+, +y+) as an Array.
    def pixel(x, y)
      raise ArgumentError, "pixel out of range" unless x.between?(0, @width - 1) && y.between?(0, @height - 1)

      offset = ((y * @width) + x) * @n
      @samples.byteslice(offset, @n).bytes
    end

    # Encode the pixmap as PNG bytes.
    def to_png
      color_type =
        case @n
        when 1 then PDF::PNG::COLOR_GRAY
        when 2 then PDF::PNG::COLOR_GRAY_ALPHA
        when 3 then PDF::PNG::COLOR_RGB
        when 4 then PDF::PNG::COLOR_RGBA
        else raise Error, "unsupported component count: #{@n}"
        end
      PDF::PNG.encode(@width, @height, @samples, color_type: color_type, bit_depth: 8)
    end

    # Write the pixmap to +path+. The extension selects the format; only PNG is
    # currently supported.
    def save(path)
      ext = ::File.extname(path).downcase.delete(".")
      unless %w[png].include?(ext)
        raise Error, "unsupported output format: #{ext.inspect} (only png)"
      end

      ::File.binwrite(path, to_png)
      path
    end
    alias write_png save

    # Raw sample bytes.
    def to_bytes
      @samples
    end

    def to_s
      "Pixmap(#{@width}x#{@height}, n=#{@n})"
    end
    alias inspect to_s
  end
end
