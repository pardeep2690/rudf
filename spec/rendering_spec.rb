# frozen_string_literal: true

require "spec_helper"

RSpec.describe "page rendering (get_pixmap)" do
  let(:pdf) { PDFBuilder.single_page(text: "Render me") }

  it "reports backend availability as a boolean" do
    expect([true, false]).to include(RUDF::Render.available?)
  end

  context "when a native backend is available" do
    before { skip "no native rendering backend in this environment" unless RUDF::Render.available? }

    it "renders a page to a Pixmap" do
      RUDF.from_bytes(pdf) do |doc|
        pix = doc[0].get_pixmap(dpi: 72)
        expect(pix).to be_a(RUDF::Pixmap)
        expect(pix.width).to be > 0
        expect(pix.height).to be > 0
      end
    end
  end

  context "when no native backend is available" do
    before { skip "a native rendering backend is present" if RUDF::Render.available? }

    it "raises a clear, actionable error" do
      RUDF.from_bytes(pdf) do |doc|
        expect { doc[0].get_pixmap }.to raise_error(RUDF::RenderingUnavailableError, /MuPDF|ffi/)
      end
    end

    it "keeps the rest of the API working without rendering" do
      RUDF.from_bytes(pdf) do |doc|
        expect(doc[0].get_text).to include("Render me")
      end
    end
  end
end
