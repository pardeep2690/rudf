# frozen_string_literal: true

# A tiny helper that assembles syntactically valid PDF byte strings for tests,
# so the suite does not depend on external fixture binaries. It emits a classic
# cross-reference table and trailer.
module PDFBuilder
  module_function

  # Build a single-page PDF whose content stream shows +text+, with the given
  # page +width+/+height+ and metadata. Returns the raw bytes.
  def single_page(text: "Hello RUDF", width: 595, height: 842, title: "RUDF Test", author: "RUDF")
    content = "BT /F1 24 Tf 72 #{height - 100} Td (#{escape(text)}) Tj ET"
    objects = []
    objects << "<< /Type /Catalog /Pages 2 0 R >>"
    objects << "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{width} #{height}] " \
               "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
    objects << "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream"
    objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    info = "<< /Title (#{escape(title)}) /Author (#{escape(author)}) /Producer (RUDF) >>"

    assemble(objects, info)
  end

  # Build a single-page PDF whose font carries a /ToUnicode CMap mapping the
  # given +code => unicode_hex+ pairs, and whose content shows +codes+ (a raw
  # byte string). Used to exercise CMap-driven text decoding.
  def tounicode_page(mapping:, codes:, width: 400, height: 800)
    bf = mapping.map { |code, hex| "<#{format('%02X', code)}> <#{hex}>" }.join("\n")
    cmap = "1 begincodespacerange <00> <ff> endcodespacerange\n" \
           "#{mapping.size} beginbfchar\n#{bf}\nendbfchar\nendcmap"
    content = "BT /F1 20 Tf 72 700 Td (#{codes.b.gsub('\\') { '\\\\' }.gsub('(', '\\(').gsub(')', '\\)')}) Tj ET"

    objects = []
    objects << "<< /Type /Catalog /Pages 2 0 R >>"
    objects << "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{width} #{height}] " \
               "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
    objects << "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream"
    objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 6 0 R >>"
    objects << "<< /Length #{cmap.bytesize} >>\nstream\n#{cmap}\nendstream"

    assemble(objects, "<< /Producer (RUDF) >>")
  end

  # Assemble numbered objects (1-based, in array order) plus an /Info dict into
  # a complete PDF with xref and trailer.
  def assemble(object_bodies, info_body)
    out = +"%PDF-1.7\n%\xE2\xE3\xCF\xD3\n"
    offsets = []
    object_bodies.each_with_index do |body, i|
      offsets << out.bytesize
      out << "#{i + 1} 0 obj\n#{body}\nendobj\n"
    end
    info_num = object_bodies.length + 1
    offsets << out.bytesize
    out << "#{info_num} 0 obj\n#{info_body}\nendobj\n"

    xref_pos = out.bytesize
    total = object_bodies.length + 2 # objects + info + free entry 0
    out << "xref\n0 #{total}\n"
    out << "0000000000 65535 f \n"
    offsets.each { |off| out << format("%010d 00000 n \n", off) }
    out << "trailer\n<< /Size #{total} /Root 1 0 R /Info #{info_num} 0 R >>\n"
    out << "startxref\n#{xref_pos}\n%%EOF\n"
    out.b
  end

  def escape(str)
    str.gsub("\\", "\\\\\\\\").gsub("(", "\\(").gsub(")", "\\)")
  end

  # Assemble a Hash of {object_number => body} (bodies without the
  # "N 0 obj/endobj" wrapper) into a complete PDF. Missing numbers become free
  # xref entries. +trailer_extra+ is appended inside the trailer dictionary.
  def assemble_numbered(objects, root: 1, trailer_extra: "")
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
    out << "trailer\n<< /Size #{max + 1} /Root #{root} 0 R #{trailer_extra} >>\n".b
    out << "startxref\n#{xref}\n%%EOF\n".b
    out.b
  end

  # A two-page PDF with an outline (TOC), link annotations (GoTo + URI) and a
  # text annotation, for exercising the navigation API.
  def annotated_doc
    page_content = "BT /F1 12 Tf 40 760 Td (Page body) Tj ET"
    objects = {
      1 => "<< /Type /Catalog /Pages 2 0 R /Outlines 8 0 R >>",
      2 => "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
      3 => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents 5 0 R " \
           "/Resources << /Font << /F1 7 0 R >> >> /Annots [11 0 R 12 0 R 13 0 R] >>",
      4 => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Contents 6 0 R " \
           "/Resources << /Font << /F1 7 0 R >> >> >>",
      5 => "<< /Length #{page_content.bytesize} >>\nstream\n#{page_content}\nendstream",
      6 => "<< /Length #{page_content.bytesize} >>\nstream\n#{page_content}\nendstream",
      7 => "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      8 => "<< /Type /Outlines /First 9 0 R /Last 10 0 R /Count 3 >>",
      9 => "<< /Title (Chapter 1) /Parent 8 0 R /Next 10 0 R /Dest [3 0 R /XYZ 0 800 0] >>",
      10 => "<< /Title (Chapter 2) /Parent 8 0 R /Prev 9 0 R /First 14 0 R /Last 14 0 R " \
            "/Count 1 /Dest [4 0 R /XYZ 0 800 0] >>",
      14 => "<< /Title (Section 2.1) /Parent 10 0 R /Dest [4 0 R /XYZ 0 400 0] >>",
      11 => "<< /Type /Annot /Subtype /Link /Rect [10 10 100 30] /Dest [4 0 R /XYZ 0 800 0] >>",
      12 => "<< /Type /Annot /Subtype /Link /Rect [10 40 200 60] " \
            "/A << /S /URI /URI (https://example.com) >> >>",
      13 => "<< /Type /Annot /Subtype /Text /Rect [300 700 320 720] /Contents (A note) /T (Reviewer) >>"
    }
    assemble_numbered(objects)
  end
end
