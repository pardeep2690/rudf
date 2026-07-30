# frozen_string_literal: true

module RUDF
  # Bridge to the optional MuPDF C extension (see +ext/rudf_native+).
  #
  # When the compiled extension is present, this exposes the full MuPDF engine
  # for rendering and high-fidelity text extraction. When it is not (pure-Ruby
  # install, or MuPDF unavailable at build time), {available?} is false and the
  # pure-Ruby implementations remain in charge.
  module Native
    # Attempt to load the compiled extension exactly once.
    @loaded =
      begin
        require "rudf/rudf_native"
        true
      rescue LoadError
        false
      end

    module_function

    # True when the native MuPDF backend is compiled in and usable.
    def available?
      @loaded && defined?(RUDF::NativeExt)
    end

    # The MuPDF version the extension was built against, or +nil+.
    def mupdf_version
      available? ? RUDF::NativeExt::MUPDF_VERSION : nil
    end

    # Explanation for why the native backend is unavailable.
    def reason
      return nil if available?

      "the native MuPDF extension is not built — install MuPDF and reinstall " \
        "the gem, or use a precompiled platform gem"
    end

    # Render page +number+ (0-based) of raw PDF +data+ using +matrix+ (a
    # {RUDF::Matrix}); returns a {RUDF::Pixmap}.
    def render(data:, number:, matrix:, alpha: false, gray: false)
      raise RenderingUnavailableError, reason unless available?

      doc = RUDF::NativeExt.open(data)
      begin
        width, height, n, samples =
          doc.render(number, matrix.a, matrix.b, matrix.c, matrix.d,
                     matrix.e, matrix.f, alpha, gray)
        RUDF::Pixmap.new(width: width, height: height, n: n, samples: samples)
      ensure
        doc.close
      end
    end

    # Extract page text through MuPDF's structured-text engine.
    def text(data:, number:)
      raise RenderingUnavailableError, reason unless available?

      doc = RUDF::NativeExt.open(data)
      begin
        doc.text(number)
      ensure
        doc.close
      end
    end
  end
end
