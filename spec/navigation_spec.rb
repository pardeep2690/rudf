# frozen_string_literal: true

require "spec_helper"

RSpec.describe "navigation (TOC, links, annotations)" do
  let(:pdf) { PDFBuilder.annotated_doc }

  describe "#get_toc" do
    it "returns nested [level, title, page] entries" do
      RUDF.from_bytes(pdf) do |doc|
        expect(doc.get_toc).to eq(
          [
            [1, "Chapter 1", 1],
            [1, "Chapter 2", 2],
            [2, "Section 2.1", 2]
          ]
        )
      end
    end

    it "returns [] for documents without an outline" do
      RUDF.from_bytes(PDFBuilder.single_page) { |doc| expect(doc.get_toc).to eq([]) }
    end

    it "includes destination details when simple is false" do
      RUDF.from_bytes(pdf) do |doc|
        entry = doc.get_toc(simple: false).first
        expect(entry[3][:kind]).to eq(:goto)
        expect(entry[3][:page]).to eq(0)
      end
    end
  end

  describe "Page#links" do
    it "extracts GoTo and URI links with page-space rects" do
      RUDF.from_bytes(pdf) do |doc|
        links = doc[0].links
        goto = links.find { |l| l[:kind] == :goto }
        uri = links.find { |l| l[:kind] == :uri }

        expect(goto[:page]).to eq(1)
        expect(goto[:from]).to be_a(RUDF::Rect)
        expect(uri[:uri]).to eq("https://example.com")
      end
    end

    it "reports link rects with a top-left origin" do
      RUDF.from_bytes(pdf) do |doc|
        # Rect [10 10 100 30] on an 800pt page -> y flips near the bottom.
        goto = doc[0].links.find { |l| l[:kind] == :goto }
        expect(goto[:from].y1).to be_within(0.01).of(790.0)
      end
    end
  end

  describe "Page#annots" do
    it "returns annotation objects with type, rect and content" do
      RUDF.from_bytes(pdf) do |doc|
        annots = doc[0].annots
        text = annots.find { |a| a.type == "Text" }
        expect(text.content).to eq("A note")
        expect(text.info[:title]).to eq("Reviewer")
        expect(text.rect).to be_a(RUDF::Rect)
      end
    end

    it "includes link annotations too" do
      RUDF.from_bytes(pdf) do |doc|
        expect(doc[0].annots.map(&:type)).to include("Link", "Text")
      end
    end
  end
end
