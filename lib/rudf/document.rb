# frozen_string_literal: true

require_relative "pdf/file"
require_relative "page"

module RUDF
  # A PDF document, the entry point of the library and a port of
  # +fitz.Document+ / +fitz.open+.
  #
  #   doc = RUDF.open("file.pdf")
  #   doc.page_count      #=> 3
  #   doc.metadata        #=> { "title" => "...", "author" => "...", ... }
  #   doc.each_page { |page| puts page.get_text }
  #   doc.close
  #
  # Documents are enumerable over their pages and may be used with a block
  # form ({RUDF.open}) that closes them automatically.
  class Document
    include Enumerable

    # Inheritable attributes propagated down the page tree per the PDF spec.
    INHERITABLE = %w[MediaBox CropBox Rotate Resources].freeze

    attr_reader :name

    # Open from a file path or from an in-memory byte string via +stream:+.
    def initialize(filename = nil, stream: nil)
      @closed = false
      @name = filename
      data =
        if stream
          stream
        elsif filename
          unless ::File.exist?(filename)
            raise FileNotFoundError, "no such file: #{filename}"
          end

          ::File.binread(filename)
        else
          raise ArgumentError, "provide a filename or stream:"
        end

      @pdf = PDF::File.new(data)
      @pages = nil
    end

    # The low-level {PDF::File}. Exposed for {Page} and advanced use.
    def pdf
      ensure_open
      @pdf
    end

    # Number of pages in the document.
    def page_count
      pages.length
    end
    alias length page_count
    alias size page_count
    alias count page_count

    # Always true for now; kept for API parity with PyMuPDF.
    def pdf?
      true
    end
    alias is_pdf pdf?

    def closed?
      @closed
    end

    # Load the page at +index+ (negative indexes count from the end).
    def load_page(index)
      ensure_open
      list = pages
      index += list.length if index.negative?
      unless index.between?(0, list.length - 1)
        raise PageNotFoundError, "page #{index} not in 0...#{list.length}"
      end

      Page.new(self, index, list[index])
    end
    alias [] load_page

    # Iterate over every {Page}.
    def each_page
      return enum_for(:each_page) unless block_given?

      page_count.times { |i| yield load_page(i) }
    end
    alias each each_page

    # Document metadata, keyed like +fitz.Document.metadata+.
    def metadata
      ensure_open
      info = @pdf.info || {}
      {
        "format" => "PDF #{@pdf.version}",
        "title" => info_string(info, "Title"),
        "author" => info_string(info, "Author"),
        "subject" => info_string(info, "Subject"),
        "keywords" => info_string(info, "Keywords"),
        "creator" => info_string(info, "Creator"),
        "producer" => info_string(info, "Producer"),
        "creationDate" => info_string(info, "CreationDate"),
        "modDate" => info_string(info, "ModDate"),
        "encryption" => nil
      }
    end

    # Close the document and release parsed data.
    def close
      @closed = true
      @pdf = nil
      @pages = nil
      nil
    end

    def to_s
      state = @closed ? "closed" : "#{page_count} pages"
      "Document(#{@name || '<stream>'}, #{state})"
    end
    alias inspect to_s

    private

    def ensure_open
      raise DocumentClosedError, "document is closed" if @closed
    end

    # Flatten the page tree into an ordered list of leaf page dictionaries,
    # merging inheritable attributes from ancestors.
    def pages
      ensure_open
      @pages ||= begin
        catalog = @pdf.catalog
        raise FileDataError, "no document catalog found" unless catalog.is_a?(Hash)

        root = @pdf.resolve(catalog["Pages"])
        collected = []
        walk_pages(root, {}, collected, {}) if root.is_a?(Hash)
        collected
      end
    end

    def walk_pages(node, inherited, collected, seen)
      return unless node.is_a?(Hash)

      type = node["Type"]
      merged = inherited.dup
      INHERITABLE.each { |key| merged[key] = node[key] if node.key?(key) }

      if type.is_a?(PDF::Name) && type.value == "Pages"
        kids = @pdf.resolve(node["Kids"])
        return unless kids.is_a?(Array)

        kids.each do |kid_ref|
          # Guard against cyclic /Kids references in malformed files.
          key = kid_ref.is_a?(PDF::Reference) ? kid_ref.number : kid_ref.object_id
          next if seen[key]

          seen[key] = true
          walk_pages(@pdf.resolve(kid_ref), merged, collected, seen)
        end
      else
        # Leaf page node (Type /Page, or untyped leaf).
        page_dict = merged.merge(node)
        collected << page_dict
      end
    end

    def info_string(info, key)
      value = @pdf.resolve(info[key])
      return nil unless value.is_a?(String)

      decode_text_string(value)
    end

    # Decode a PDF text string (UTF-16BE with BOM, or PDFDocEncoding/Latin-1).
    def decode_text_string(str)
      bytes = str.b
      if bytes.start_with?("\xFE\xFF".b)
        bytes[2..].force_encoding(Encoding::UTF_16BE).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      else
        bytes.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      str
    end
  end
end
