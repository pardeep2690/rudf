# frozen_string_literal: true

require_relative "pdf/text_writer"
require_relative "pdf/serializer"

module RUDF
  # Adds in-place text stamping to {Document}: draw text onto existing pages
  # and write the result as an incremental update (the original bytes are kept
  # intact and the new objects are appended). Encrypted documents are not
  # editable.
  #
  # Coordinates use the top-left origin (y downward) that the readers report.
  module Editing
    # Draw a single line of text with its baseline at +point+ ([x, y]) on the
    # page at +page_index+.
    def insert_text(page_index, point, text, fontsize: 11, fontname: "helv", color: nil)
      stamp(page_index) do |content, height|
        font = PDF::StandardFont.new(fontname)
        x, y = point
        content.draw_line(x, height - y, text, font, fontsize, color)
      end
      self
    end

    # Draw +text+ inside +rect+ ([x0, y0, x1, y1], top-left origin) on the page
    # at +page_index+, with alignment and (default) vertical centering.
    def insert_textbox(page_index, rect, text, fontsize: 11, fontname: "helv",
                       align: :center, valign: :center, color: nil, line_spacing: 1.2)
      stamp(page_index) do |content, height|
        font = PDF::StandardFont.new(fontname)
        PDF::TextLayout.place(
          content: content, rect: rect, text: text, font: font, size: fontsize,
          page_height: height, align: align, valign: valign,
          color: color, line_spacing: line_spacing
        )
      end
      self
    end

    # Serialize the document with all pending edits applied. Writes to +path+
    # when given, otherwise returns the bytes. With no edits, returns the
    # original bytes unchanged.
    def save(path = nil)
      ensure_open
      bytes = pending_edits? ? build_incremental : @pdf.raw_bytes
      if path
        ::File.binwrite(path, bytes)
        path
      else
        bytes
      end
    end

    private

    def pending_edits?
      @edits && @edits.any? { |_, e| !e[:content].empty? }
    end

    def stamp(page_index)
      ensure_open
      raise Error, "cannot edit an encrypted document" if @pdf.encrypted?

      pages # ensure @page_refs is built
      raise PageNotFoundError, "page #{page_index} out of range" unless @page_refs[page_index]

      @edits ||= {}
      entry = (@edits[page_index] ||= { content: PDF::TextContent.new })
      height = load_page(page_index).mediabox.height
      yield(entry[:content], height)
    end

    def build_incremental
      out = +@pdf.raw_bytes.b
      out << "\n" unless out.end_with?("\n")
      next_num = @pdf.max_object_number + 1
      offsets = {}

      @edits.each do |page_index, entry|
        content = entry[:content]
        next if content.empty?

        content_num = next_num
        next_num += 1
        font_nums = {}
        content.fonts.values.uniq.each do |base|
          font_nums[base] = next_num
          next_num += 1
        end

        write_object(out, content_num, content_stream_body(content.bytes), offsets)
        font_nums.each { |base, num| write_object(out, num, font_dict_body(base), offsets) }

        page_num = @page_refs[page_index]
        new_page = updated_page(page_num, page_index, content_num, content, font_nums)
        write_object(out, page_num, PDF::Serializer.serialize(new_page), offsets)
      end

      append_incremental_xref(out, offsets)
      out
    end

    def updated_page(page_num, page_index, content_num, content, font_nums)
      dict = @pdf.object(page_num).dup
      new_ref = PDF::Reference.new(content_num, 0)

      contents = dict["Contents"]
      dict["Contents"] =
        case contents
        when Array then contents + [new_ref]
        when nil then [new_ref]
        else [contents, new_ref]
        end

      resources = effective_resources(page_num, page_index).dup
      font_res = existing_font_resources(resources)
      content.fonts.each { |name, base| font_res[name] = PDF::Reference.new(font_nums[base], 0) }
      resources["Font"] = font_res
      dict["Resources"] = resources
      dict
    end

    def effective_resources(page_num, page_index)
      own = @pdf.resolve(@pdf.object(page_num)["Resources"])
      return own if own.is_a?(Hash)

      inherited = @pdf.resolve(pages[page_index]["Resources"])
      inherited.is_a?(Hash) ? inherited : {}
    end

    def existing_font_resources(resources)
      existing = @pdf.resolve(resources["Font"])
      existing.is_a?(Hash) ? existing.dup : {}
    end

    def write_object(out, num, body, offsets)
      offsets[num] = out.bytesize
      out << "#{num} 0 obj\n#{body}\nendobj\n".b
    end

    def content_stream_body(bytes)
      "<< /Length #{bytes.bytesize} >>\nstream\n#{bytes}\nendstream"
    end

    def font_dict_body(base)
      "<< /Type /Font /Subtype /Type1 /BaseFont /#{base} /Encoding /WinAnsiEncoding >>"
    end

    def append_incremental_xref(out, offsets)
      prev = previous_startxref
      root = @pdf.root_reference
      root_str = root.is_a?(PDF::Reference) ? "#{root.number} #{root.generation} R" : "1 0 R"
      size = [offsets.keys.max + 1, @pdf.max_object_number + 1].max

      xref_pos = out.bytesize
      out << "xref\n".b
      offsets.sort.each do |num, off|
        out << "#{num} 1\n".b
        out << format("%010d 00000 n \n", off).b
      end
      out << "trailer\n<< /Size #{size} /Root #{root_str}"
      out << " /Prev #{prev}" if prev
      out << " >>\nstartxref\n#{xref_pos}\n%%EOF\n".b
      out
    end

    def previous_startxref
      data = @pdf.raw_bytes
      idx = data.rindex("startxref")
      return nil unless idx

      data[idx + "startxref".length..].to_s[/\d+/]&.to_i
    end
  end
end
