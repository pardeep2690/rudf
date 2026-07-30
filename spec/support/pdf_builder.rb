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
end
