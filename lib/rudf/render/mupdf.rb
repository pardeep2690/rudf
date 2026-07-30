# frozen_string_literal: true

module RUDF
  module Render
    # Optional page-rendering backend that binds to the native MuPDF library
    # via FFI. It is loaded lazily and never required by the pure-Ruby core, so
    # the gem installs and runs with no native dependency; rendering simply
    # becomes available when +libmupdf+ and the +ffi+ gem are both present.
    #
    # Because struct-by-value calling conventions and symbol availability vary
    # between MuPDF releases, every step is guarded: any failure leaves the
    # backend reporting itself unavailable rather than crashing the caller.
    #
    # The expected library version can be set with +RUDF_MUPDF_VERSION+ (MuPDF
    # checks the version string when creating a context).
    module MuPDF
      LIB_NAMES = %w[mupdf libmupdf mupdf.so libmupdf.so libmupdf.dylib mupdf.dll].freeze
      DEFAULT_VERSION = "1.24.0"

      module_function

      # True when a MuPDF context can be created through FFI.
      def available?
        return @available unless @available.nil?

        @available = setup
      end

      # The reason rendering is unavailable, for user-facing error messages.
      def unavailable_reason
        @reason
      end

      # Render page +number+ of the document held in +data+ (raw PDF bytes) at
      # the given transform, returning a {RUDF::Pixmap}.
      def render(data:, number:, matrix:, alpha:, gray:)
        raise RenderingUnavailableError, install_hint unless available?

        require "tempfile"
        Tempfile.create(["rudf", ".pdf"]) do |file|
          file.binmode
          file.write(data)
          file.flush
          render_file(file.path, number, matrix, alpha, gray)
        end
      end

      def install_hint
        base = "native rendering requires the MuPDF library and the 'ffi' gem"
        @reason ? "#{base} (#{@reason})" : base
      end

      # ---- FFI setup ---------------------------------------------------------

      def setup
        require "ffi"
        build_module
        true
      rescue LoadError => e
        @reason = "could not load ffi/libmupdf: #{e.message}"
        false
      rescue StandardError => e
        @reason = e.message
        false
      end

      # Define the FFI bindings against libmupdf. Kept in a method so the
      # heavy +extend FFI::Library+ work only happens on demand.
      def build_module
        version = ENV.fetch("RUDF_MUPDF_VERSION", DEFAULT_VERSION)

        mod = Module.new do
          extend FFI::Library
          ffi_lib RUDF::Render::MuPDF::LIB_NAMES

          # fz_matrix is six floats passed and returned by value.
          matrix = Class.new(FFI::Struct) do
            layout :a, :float, :b, :float, :c, :float,
                   :d, :float, :e, :float, :f, :float
          end
          const_set(:FzMatrix, matrix)

          attach_function :fz_new_context_imp,
                          %i[pointer pointer size_t string], :pointer
          attach_function :fz_register_document_handlers, [:pointer], :void
          attach_function :fz_open_document, %i[pointer string], :pointer
          attach_function :fz_count_pages, %i[pointer pointer], :int
          attach_function :fz_device_rgb, [:pointer], :pointer
          attach_function :fz_device_gray, [:pointer], :pointer
          attach_function :fz_new_pixmap_from_page_number,
                          [:pointer, :pointer, :int, matrix.by_value, :pointer, :int], :pointer
          attach_function :fz_pixmap_width, %i[pointer pointer], :int
          attach_function :fz_pixmap_height, %i[pointer pointer], :int
          attach_function :fz_pixmap_components, %i[pointer pointer], :int
          attach_function :fz_pixmap_samples, %i[pointer pointer], :pointer
          attach_function :fz_drop_pixmap, %i[pointer pointer], :void
          attach_function :fz_drop_document, %i[pointer pointer], :void
          attach_function :fz_drop_context, [:pointer], :void
        end

        @version = version
        @lib = mod
      end

      # ---- rendering ---------------------------------------------------------

      def render_file(path, number, matrix, alpha, gray)
        ctx = @lib.fz_new_context_imp(nil, nil, 256 << 20, @version)
        raise RenderingUnavailableError, "fz_new_context failed" if ctx.null?

        begin
          @lib.fz_register_document_handlers(ctx)
          doc = @lib.fz_open_document(ctx, path)
          raise Error, "MuPDF could not open the document" if doc.null?

          begin
            pixmap_to_ruby(ctx, doc, number, matrix, alpha, gray)
          ensure
            @lib.fz_drop_document(ctx, doc)
          end
        ensure
          @lib.fz_drop_context(ctx)
        end
      end

      def pixmap_to_ruby(ctx, doc, number, matrix, alpha, gray)
        ctm = @lib::FzMatrix.new
        ctm[:a] = matrix.a
        ctm[:b] = matrix.b
        ctm[:c] = matrix.c
        ctm[:d] = matrix.d
        ctm[:e] = matrix.e
        ctm[:f] = matrix.f

        colorspace = gray ? @lib.fz_device_gray(ctx) : @lib.fz_device_rgb(ctx)
        pix = @lib.fz_new_pixmap_from_page_number(ctx, doc, number, ctm, colorspace, alpha ? 1 : 0)
        raise Error, "MuPDF failed to render the page" if pix.null?

        begin
          width = @lib.fz_pixmap_width(ctx, pix)
          height = @lib.fz_pixmap_height(ctx, pix)
          n = @lib.fz_pixmap_components(ctx, pix)
          ptr = @lib.fz_pixmap_samples(ctx, pix)
          bytes = ptr.read_bytes(width * height * n)
          RUDF::Pixmap.new(width: width, height: height, n: n, samples: bytes)
        ensure
          @lib.fz_drop_pixmap(ctx, pix)
        end
      end
    end
  end
end
