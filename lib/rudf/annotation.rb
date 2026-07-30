# frozen_string_literal: true

module RUDF
  # A page annotation, a lightweight analogue of +fitz.Annot+.
  #
  # Exposes the properties most readers need — the annotation subtype, its
  # rectangle on the page, and its author/contents metadata — without
  # attempting to reproduce MuPDF's full annotation model.
  class Annotation
    attr_reader :type, :rect, :info

    def initialize(type:, rect:, info:)
      @type = type       # subtype name, e.g. "Link", "Text", "Highlight"
      @rect = rect       # RUDF::Rect
      @info = info       # Hash: :content, :title, :name, ...
    end

    # The annotation's free-text contents (+/Contents+), or "".
    def content
      @info[:content] || ""
    end

    def to_s
      "Annotation(#{@type}, #{@rect})"
    end
    alias inspect to_s
  end
end
