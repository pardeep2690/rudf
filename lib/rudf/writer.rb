# frozen_string_literal: true

require_relative "pdf/text_writer"

module RUDF
  # Builds a new PDF document and writes text onto its pages.
  #
  # This is the write-side counterpart to {Document}. It targets the common
  # need of laying out text (titles, labels, reports) using the standard
  # fonts, with alignment and centering.
  #
  # @example A centered, bold title
  #   writer = RUDF::Writer.new
  #   page = writer.add_page(width: 595, height: 842)
  #   page.insert_textbox([0, 100, 595, 160], "Annual Report",
  #                       fontname: "Helvetica-Bold", fontsize: 28, align: :center)
  #   writer.save("report.pdf")
  class Writer
    def initialize
      @pages = []
    end

    attr_reader :pages

    # Add a page and return it for drawing. Defaults to US Letter.
    def add_page(width: 612, height: 792)
      page = Page.new(width, height)
      @pages << page
      page
    end

    # Serialize the document to PDF bytes.
    def to_bytes
      Serializer.new(@pages).build
    end

    # Write the document to +path+.
    def save(path)
      ::File.binwrite(path, to_bytes)
      path
    end

    # A page being authored. Coordinates are top-left origin (y downward), the
    # same convention used by RUDF's readers.
    class Page
      attr_reader :width, :height, :content

      def initialize(width, height)
        @width = width.to_f
        @height = height.to_f
        @content = PDF::TextContent.new
      end

      # Draw a single line of text with its baseline at +point+ ([x, y], top-
      # left origin).
      def insert_text(point, text, fontsize: 11, fontname: "helv", color: nil)
        font = PDF::StandardFont.new(fontname)
        x, y = point
        @content.draw_line(x, @height - y, text, font, fontsize, color)
        self
      end

      # Draw +text+ inside +rect+ ([x0, y0, x1, y1], top-left origin) with the
      # given alignment. Text is wrapped to the box width and, by default,
      # centered vertically within the box's height.
      #
      # @return [Array<Float>] the bounds actually covered by the text
      def insert_textbox(rect, text, fontsize: 11, fontname: "helv",
                         align: :center, valign: :center, color: nil, line_spacing: 1.2)
        font = PDF::StandardFont.new(fontname)
        PDF::TextLayout.place(
          content: @content, rect: rect, text: text, font: font, size: fontsize,
          page_height: @height, align: align, valign: valign,
          color: color, line_spacing: line_spacing
        )
      end
    end

    # Assembles authored pages into a complete PDF byte string.
    class Serializer
      def initialize(pages)
        @pages = pages
      end

      def build
        objects = {}
        # Object numbering: 1 catalog, 2 pages tree, then fonts, then per-page
        # (page dict + content stream).
        font_objs = assign_fonts
        next_num = 3 + font_objs.size
        page_nums = []

        @pages.each do |page|
          page_num = next_num
          content_num = next_num + 1
          next_num += 2
          page_nums << page_num
          objects[page_num] = page_dict(page, content_num, font_objs)
          objects[content_num] = content_stream(page.content.bytes)
        end

        objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
        objects[2] = "<< /Type /Pages /Kids [#{page_nums.map { |n| "#{n} 0 R" }.join(' ')}] " \
                     "/Count #{@pages.size} >>"
        font_objs.each { |base, num| objects[num] = font_dict(base) }

        assemble(objects)
      end

      private

      # Collect every base font used across all pages -> object number.
      def assign_fonts
        bases = @pages.flat_map { |p| p.content.fonts.values }.uniq
        map = {}
        bases.each_with_index { |base, i| map[base] = 3 + i }
        map
      end

      def page_dict(page, content_num, font_objs)
        fonts = page.content.fonts.map do |name, base|
          "/#{name} #{font_objs[base]} 0 R"
        end.join(" ")
        resources = fonts.empty? ? "<< >>" : "<< /Font << #{fonts} >> >>"
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{num(page.width)} #{num(page.height)}] " \
          "/Resources #{resources} /Contents #{content_num} 0 R >>"
      end

      def content_stream(bytes)
        "<< /Length #{bytes.bytesize} >>\nstream\n#{bytes}\nendstream"
      end

      def font_dict(base)
        "<< /Type /Font /Subtype /Type1 /BaseFont /#{base} /Encoding /WinAnsiEncoding >>"
      end

      def assemble(objects)
        out = +"%PDF-1.7\n%\xE2\xE3\xCF\xD3\n".b
        offsets = {}
        max = objects.keys.max
        objects.keys.sort.each do |num|
          offsets[num] = out.bytesize
          out << "#{num} 0 obj\n#{objects[num]}\nendobj\n".b
        end
        xref = out.bytesize
        out << "xref\n0 #{max + 1}\n0000000000 65535 f \n".b
        (1..max).each do |num|
          out << (offsets[num] ? format("%010d 00000 n \n", offsets[num]) : "0000000000 00000 f \n").b
        end
        out << "trailer\n<< /Size #{max + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
        out.b
      end

      def num(value)
        f = value.to_f
        f == f.to_i ? f.to_i.to_s : f.to_s
      end
    end
  end
end
