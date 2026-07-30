# frozen_string_literal: true

require_relative "pdf/text_page"

module RUDF
  # A single page of a {Document}, mirroring the surface of +fitz.Page+.
  #
  #   doc = RUDF.open("file.pdf")
  #   page = doc[0]
  #   page.rect        #=> Rect(0, 0, 595, 842)
  #   page.rotation    #=> 0
  #   page.get_text    #=> "extracted text ..."
  class Page
    # Inheritable page-tree attributes are already merged into +dict+ by the
    # {Document} that builds the page.
    attr_reader :number, :dict

    def initialize(document, number, dict)
      @document = document
      @number = number
      @dict = dict
    end

    # The page's media box (the physical page boundary), as a {Rect}.
    def mediabox
      box = @document.pdf.resolve(@dict["MediaBox"])
      return Rect.new(0, 0, 612, 792) unless box.is_a?(Array) && box.length == 4

      coords = box.map { |v| @document.pdf.resolve(v).to_f }
      Rect.new(*coords).normalize
    end

    # The crop box, defaulting to the media box.
    def cropbox
      box = @document.pdf.resolve(@dict["CropBox"])
      return mediabox unless box.is_a?(Array) && box.length == 4

      coords = box.map { |v| @document.pdf.resolve(v).to_f }
      Rect.new(*coords).normalize
    end

    # Clockwise display rotation in degrees (0, 90, 180 or 270).
    def rotation
      value = @document.pdf.resolve(@dict["Rotate"]).to_i
      value %= 360
      value += 360 if value < 0
      value
    end

    # The page rectangle with its top-left corner at the origin, accounting for
    # rotation, analogous to +fitz.Page.rect+.
    def rect
      mb = mediabox
      if [90, 270].include?(rotation)
        Rect.new(0, 0, mb.height, mb.width)
      else
        Rect.new(0, 0, mb.width, mb.height)
      end
    end
    alias bound rect

    def width
      rect.width
    end

    def height
      rect.height
    end

    # Extract text from the page, mirroring +fitz.Page.get_text+.
    #
    # Supported modes:
    # * +"text"+   – plain text (default)
    # * +"words"+  – array of +[x0, y0, x1, y1, word, block, line, word_no]+
    # * +"blocks"+ – array of +[x0, y0, x1, y1, text, block, type]+
    # * +"dict"+   – nested Hash of blocks → lines → spans with bounding boxes
    def get_text(option = "text")
      tp = text_page
      case option.to_s
      when "text" then tp.text
      when "words" then tp.words
      when "blocks" then tp.blocks
      when "dict", "rawdict" then tp.dict
      else
        raise ArgumentError, "unsupported text extraction mode: #{option.inspect}"
      end
    end
    alias text get_text

    # The parsed {PDF::TextPage} for this page (structured text with geometry).
    def text_page
      @text_page ||= begin
        mb = mediabox
        PDF::TextPage.new(
          contents,
          resources: @document.pdf.resolve(@dict["Resources"]),
          resolver: @document.pdf.method(:resolve),
          page_height: mb.height,
          page_width: mb.width
        )
      end
    end

    # The raw, concatenated (and filter-decoded) content streams of the page.
    def contents
      entry = @document.pdf.resolve(@dict["Contents"])
      streams =
        case entry
        when Array then entry.map { |ref| @document.pdf.resolve(ref) }
        else [entry]
        end
      streams.filter_map do |stream|
        stream.decoded if stream.is_a?(PDF::Stream)
      end.join("\n")
    end

    def to_s
      "Page(number=#{@number}, rect=#{rect})"
    end
    alias inspect to_s
  end
end
