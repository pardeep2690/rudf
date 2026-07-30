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

    # Link annotations on the page, mirroring +fitz.Page.get_links+.
    #
    # Each link is a Hash with +:kind+ (+:goto+, +:uri+, +:remote+ or +:none+),
    # +:from+ (a {Rect} in top-left page coordinates), and, depending on kind,
    # +:page+ (0-based target index), +:to+ (a {Point}) and +:uri+.
    def links
      annotation_dicts.filter_map do |annot|
        subtype = @document.pdf.resolve(annot["Subtype"])
        next unless subtype.is_a?(PDF::Name) && subtype.value == "Link"

        dest = link_destination(annot)
        { from: rect_from_array(annot["Rect"]) }.merge(dest)
      end
    end
    alias get_links links

    # All annotations on the page as {Annotation} objects.
    def annots
      annotation_dicts.filter_map do |annot|
        subtype = @document.pdf.resolve(annot["Subtype"])
        Annotation.new(
          type: subtype.is_a?(PDF::Name) ? subtype.value : "Unknown",
          rect: rect_from_array(annot["Rect"]),
          info: {
            content: text_value(annot["Contents"]),
            title: text_value(annot["T"]),
            name: name_value(annot["Name"])
          }
        )
      end
    end
    alias annotations annots
    alias get_annots annots

    def to_s
      "Page(number=#{@number}, rect=#{rect})"
    end
    alias inspect to_s

    private

    def annotation_dicts
      annots = @document.pdf.resolve(@dict["Annots"])
      return [] unless annots.is_a?(Array)

      annots.filter_map do |ref|
        dict = @document.pdf.resolve(ref)
        dict if dict.is_a?(Hash)
      end
    end

    def link_destination(annot)
      if annot.key?("Dest")
        @document.resolve_destination(annot["Dest"])
      elsif annot.key?("A")
        @document.send(:resolve_action, @document.pdf.resolve(annot["A"]))
      else
        { kind: :none, page: nil, to: nil, uri: nil }
      end
    end

    # Convert a PDF +[x0 y0 x1 y1]+ rectangle (bottom-left origin) into a
    # top-left-origin {Rect}, matching the text-extraction coordinate system.
    def rect_from_array(value)
      arr = @document.pdf.resolve(value)
      return Rect.new(0, 0, 0, 0) unless arr.is_a?(Array) && arr.length == 4

      coords = arr.map { |v| @document.pdf.resolve(v).to_f }
      r = Rect.new(*coords).normalize
      h = mediabox.height
      Rect.new(r.x0, h - r.y1, r.x1, h - r.y0)
    end

    def text_value(value)
      str = @document.pdf.resolve(value)
      return nil unless str.is_a?(String)

      @document.send(:decode_text_string, str)
    end

    def name_value(value)
      v = @document.pdf.resolve(value)
      v.is_a?(PDF::Name) ? v.value : nil
    end
  end
end
