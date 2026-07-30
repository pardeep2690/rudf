# frozen_string_literal: true

require_relative "rudf/version"
require_relative "rudf/errors"

# Geometry primitives (ported from fitz).
require_relative "rudf/geometry/point"
require_relative "rudf/geometry/matrix"
require_relative "rudf/geometry/rect"
require_relative "rudf/geometry/irect"
require_relative "rudf/geometry/quad"

# High-level document model.
require_relative "rudf/document"
require_relative "rudf/page"

# RUDF ("Ruby PDF") is a pure-Ruby port of the PyMuPDF (+fitz+) library.
#
# It provides PyMuPDF's document model — {Document}, {Page} and the geometry
# primitives {Point}, {Matrix}, {Rect}, {IRect} and {Quad} — backed by a
# self-contained PDF parser, so it runs with no native dependencies.
#
# @example Read a PDF
#   RUDF.open("report.pdf") do |doc|
#     puts doc.page_count
#     puts doc[0].get_text
#   end
module RUDF
  class << self
    # Open a PDF from a file path or an in-memory byte string.
    #
    # With a block, the document is yielded and closed automatically; without
    # one, the caller owns the returned {Document} and should {Document#close}
    # it when done.
    #
    # @param filename [String, nil] path to a PDF file
    # @param stream [String, nil] raw PDF bytes (alternative to +filename+)
    # @return [Document] when called without a block
    def open(filename = nil, stream: nil)
      doc = Document.new(filename, stream: stream)
      return doc unless block_given?

      begin
        yield doc
      ensure
        doc.close
      end
    end
    alias read open

    # Open a document directly from a byte string.
    def from_bytes(bytes, &block)
      open(nil, stream: bytes, &block)
    end
  end
end
