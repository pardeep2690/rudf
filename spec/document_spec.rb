# frozen_string_literal: true

require "spec_helper"

RSpec.describe RUDF::Document do
  let(:pdf_bytes) do
    PDFBuilder.single_page(text: "Hello RUDF", width: 595, height: 842,
                           title: "RUDF Test", author: "Pardeep")
  end

  describe "opening" do
    it "opens from an in-memory byte string" do
      doc = RUDF.open(nil, stream: pdf_bytes)
      expect(doc).to be_a(described_class)
      expect(doc.page_count).to eq(1)
      doc.close
    end

    it "yields and auto-closes with a block" do
      closed = nil
      RUDF.open(nil, stream: pdf_bytes) do |doc|
        expect(doc.page_count).to eq(1)
        closed = doc
      end
      expect(closed).to be_closed
    end

    it "raises for a missing file" do
      expect { RUDF.open("/no/such/file.pdf") }.to raise_error(RUDF::FileNotFoundError)
    end

    it "raises for non-PDF data" do
      expect { RUDF.open(nil, stream: "not a pdf") }.to raise_error(RUDF::FileDataError)
    end
  end

  describe "metadata" do
    it "reads the info dictionary" do
      RUDF.from_bytes(pdf_bytes) do |doc|
        meta = doc.metadata
        expect(meta["title"]).to eq("RUDF Test")
        expect(meta["author"]).to eq("Pardeep")
        expect(meta["format"]).to start_with("PDF 1.")
      end
    end
  end

  describe "pages" do
    it "loads a page and reports its geometry" do
      RUDF.from_bytes(pdf_bytes) do |doc|
        page = doc[0]
        expect(page).to be_a(RUDF::Page)
        expect(page.rect).to eq(RUDF::Rect.new(0, 0, 595, 842))
        expect(page.rotation).to eq(0)
        expect(page.number).to eq(0)
      end
    end

    it "raises for out-of-range pages" do
      RUDF.from_bytes(pdf_bytes) do |doc|
        expect { doc[5] }.to raise_error(RUDF::PageNotFoundError)
      end
    end

    it "is enumerable over pages" do
      RUDF.from_bytes(pdf_bytes) do |doc|
        rects = doc.each_page.map(&:rect)
        expect(rects.length).to eq(1)
      end
    end
  end

  describe "text extraction" do
    it "extracts visible text from the content stream" do
      RUDF.from_bytes(pdf_bytes) do |doc|
        expect(doc[0].get_text).to include("Hello RUDF")
      end
    end
  end

  describe "closed documents" do
    it "raises once closed" do
      doc = RUDF.open(nil, stream: pdf_bytes)
      doc.close
      expect { doc.page_count }.to raise_error(RUDF::DocumentClosedError)
    end
  end
end
