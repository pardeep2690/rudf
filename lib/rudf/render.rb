# frozen_string_literal: true

require_relative "native"
require_relative "render/mupdf"

module RUDF
  # Facade over the optional page-rendering backends.
  #
  # Rendering is not part of the pure-Ruby core: it requires a native engine.
  # {available?} reports whether one is usable, and {render} either produces a
  # {Pixmap} or raises {RenderingUnavailableError} with an actionable message.
  module Render
    module_function

    # True when any native rendering backend is usable in this environment.
    # The compiled MuPDF extension is preferred; the FFI backend is a fallback
    # for when only a system libmupdf (and the +ffi+ gem) is present.
    def available?
      Native.available? || MuPDF.available?
    end

    # Render +number+ (0-based) of the document bytes +data+ using +matrix+.
    def render(data:, number:, matrix:, alpha: false, gray: false)
      if Native.available?
        Native.render(data: data, number: number, matrix: matrix, alpha: alpha, gray: gray)
      elsif MuPDF.available?
        MuPDF.render(data: data, number: number, matrix: matrix, alpha: alpha, gray: gray)
      else
        raise RenderingUnavailableError, unavailable_reason
      end
    end

    # Human-readable explanation of why rendering is unavailable.
    def unavailable_reason
      Native.reason || MuPDF.install_hint
    end
  end
end
