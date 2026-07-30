# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "writing text" do
  describe RUDF::PDF::StandardFont do
    it "measures known Helvetica and Helvetica-Bold glyph widths" do
      expect(described_class.new("Helvetica").char_width("A".ord)).to eq(667)
      expect(described_class.new("Helvetica-Bold").char_width("A".ord)).to eq(722)
    end

    it "resolves PyMuPDF-style aliases" do
      expect(described_class.new("hebo").base).to eq("Helvetica-Bold")
      expect(described_class.new("helv")).not_to be_bold
      expect(described_class.new("hebo")).to be_bold
    end

    it "scales text width by size" do
      font = described_class.new("Helvetica")
      expect(font.text_width("AA", 20)).to be_within(0.001).of(667 * 2 / 1000.0 * 20)
    end
  end

  describe RUDF::Writer do
    it "creates an openable single-page PDF" do
      writer = described_class.new
      writer.add_page(width: 300, height: 400)
      RUDF.from_bytes(writer.to_bytes) do |doc|
        expect(doc.page_count).to eq(1)
        expect(doc[0].rect).to eq(RUDF::Rect.new(0, 0, 300, 400))
      end
    end

    it "centers a bold line horizontally within the box" do
      writer = described_class.new
      page = writer.add_page(width: 400, height: 600)
      page.insert_textbox([0, 200, 400, 260], "CENTERED BOLD",
                          fontname: "Helvetica-Bold", fontsize: 28, align: :center)
      RUDF.from_bytes(writer.to_bytes) do |doc|
        words = doc[0].get_text("words")
        x0 = words.map { |w| w[0] }.min
        x1 = words.map { |w| w[2] }.max
        expect((x0 + x1) / 2.0).to be_within(0.5).of(200.0) # page center
        expect(x0).to be_within(0.5).of(400 - x1)           # equal margins
      end
    end

    it "places the text vertically within the given band" do
      writer = described_class.new
      page = writer.add_page(width: 400, height: 600)
      page.insert_textbox([0, 200, 400, 280], "BAND", fontname: "Helvetica-Bold",
                          fontsize: 24, align: :center, valign: :center)
      RUDF.from_bytes(writer.to_bytes) do |doc|
        y0 = doc[0].get_text("words").map { |w| w[1] }.min
        y1 = doc[0].get_text("words").map { |w| w[3] }.max
        cy = (y0 + y1) / 2.0
        expect(cy).to be_between(200, 280)        # inside the band
        expect(cy).to be_within(6).of(240)        # near the band centre
      end
    end

    it "saves to a file" do
      Tempfile.create(["w", ".pdf"]) do |f|
        writer = described_class.new
        writer.add_page.insert_text([72, 72], "Hello", fontsize: 12, fontname: "helv")
        writer.save(f.path)
        RUDF.open(f.path) { |doc| expect(doc[0].get_text).to include("Hello") }
      end
    end
  end

  describe "stamping onto an existing document" do
    let(:original) { PDFBuilder.single_page(text: "Original body", width: 400, height: 600) }

    it "appends text and preserves the original content" do
      doc = RUDF.open(nil, stream: original)
      doc.insert_textbox(0, [0, 40, 400, 90], "STAMPED", fontname: "Helvetica-Bold",
                         fontsize: 24, align: :center)
      edited = doc.save
      doc.close

      expect(edited.bytesize).to be > original.bytesize
      RUDF.from_bytes(edited) do |d|
        text = d[0].get_text
        expect(text).to include("STAMPED")
        expect(text).to include("Original body")
      end
    end

    it "returns the original bytes unchanged when there are no edits" do
      doc = RUDF.open(nil, stream: original)
      expect(doc.save).to eq(original)
      doc.close
    end

    it "refuses to edit an encrypted document" do
      require_relative "support/encrypted_pdf_builder"
      enc = EncryptedPDFBuilder.single_page(method: :rc4)
      doc = RUDF.open(nil, stream: enc)
      expect { doc.insert_text(0, [10, 10], "x") }.to raise_error(RUDF::Error)
      doc.close
    end
  end
end
