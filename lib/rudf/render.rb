# frozen_string_literal: true

require_relative "render/mupdf"

module RUDF
  # Facade over the optional page-rendering backends.
  #
  # Rendering is not part of the pure-Ruby core: it requires a native engine.
  # {available?} reports whether one is usable, and {render} either produces a
  # {Pixmap} or raises {RenderingUnavailableError} with an actionable message.
  module Render
    module_function

    # True when a native rendering backend is usable in this environment.
    def available?
      MuPDF.available?
    end

    # Render +number+ (0-based) of the document bytes +data+ using +matrix+.
    def render(data:, number:, matrix:, alpha: false, gray: false)
      MuPDF.render(data: data, number: number, matrix: matrix, alpha: alpha, gray: gray)
    end

    # Human-readable explanation of why rendering is unavailable.
    def unavailable_reason
      MuPDF.install_hint
    end
  end
end
