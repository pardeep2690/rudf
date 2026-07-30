# frozen_string_literal: true

require "spec_helper"

RSpec.describe "text extraction" do
  describe "ToUnicode CMap decoding" do
    let(:pdf) do
      # Map byte codes 1,2,3 to H, i, ! (deliberately not their ASCII values)
      # so a correct decode proves the CMap is being used.
      PDFBuilder.tounicode_page(
        mapping: { 1 => "0048", 2 => "0069", 3 => "0021" },
        codes: "\x01\x02\x03"
      )
    end

    it "decodes character codes through the /ToUnicode map" do
      RUDF.from_bytes(pdf) { |doc| expect(doc[0].get_text).to eq("Hi!") }
    end

    it "decodes multi-unit destinations (ligatures, astral chars)" do
      pdf = PDFBuilder.tounicode_page(mapping: { 1 => "0066006C" }, codes: "\x01")
      RUDF.from_bytes(pdf) { |doc| expect(doc[0].get_text).to eq("fl") }
    end
  end

  describe "extraction modes" do
    let(:pdf) do
      PDFBuilder.tounicode_page(
        mapping: { 1 => "0048", 2 => "0069", 3 => "0021" },
        codes: "\x01\x02\x03"
      )
    end

    it "words mode returns tuples with a bounding box and indices" do
      RUDF.from_bytes(pdf) do |doc|
        words = doc[0].get_text("words")
        expect(words.length).to eq(1)
        x0, y0, x1, y1, text, block, line, wno = words.first
        expect(text).to eq("Hi!")
        expect([block, line, wno]).to eq([0, 0, 0])
        expect(x1).to be > x0
        expect(y1).to be > y0
      end
    end

    it "blocks mode returns text with a type flag" do
      RUDF.from_bytes(pdf) do |doc|
        blocks = doc[0].get_text("blocks")
        expect(blocks.first[4]).to eq("Hi!")
        expect(blocks.first[6]).to eq(0) # text block
      end
    end

    it "dict mode returns a nested block/line/span structure" do
      RUDF.from_bytes(pdf) do |doc|
        d = doc[0].get_text("dict")
        span = d[:blocks][0][:lines][0][:spans][0]
        expect(span[:text]).to eq("Hi!")
        expect(span[:size]).to eq(20.0)
        expect(span[:bbox].length).to eq(4)
      end
    end

    it "reports coordinates with a top-left origin" do
      RUDF.from_bytes(pdf) do |doc|
        # Text drawn near the top of an 800pt page should have small y values.
        _, y0, = doc[0].get_text("words").first
        expect(y0).to be < 200
      end
    end

    it "rejects unknown modes" do
      RUDF.from_bytes(pdf) do |doc|
        expect { doc[0].get_text("nope") }.to raise_error(ArgumentError)
      end
    end
  end
end
