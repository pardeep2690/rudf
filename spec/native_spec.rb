# frozen_string_literal: true

require "spec_helper"

RSpec.describe RUDF::Native do
  it "reports availability as a boolean" do
    expect([true, false]).to include(described_class.available?)
  end

  context "when the native extension is not compiled" do
    before { skip "native extension is present" if described_class.available? }

    it "gives a clear reason" do
      expect(described_class.reason).to match(/native MuPDF extension/)
    end

    it "has no MuPDF version" do
      expect(described_class.mupdf_version).to be_nil
    end

    it "raises RenderingUnavailableError from render" do
      expect do
        described_class.render(data: "x", number: 0, matrix: RUDF::IDENTITY)
      end.to raise_error(RUDF::RenderingUnavailableError)
    end
  end

  context "when the native extension is compiled" do
    before { skip "native extension not built in this environment" unless described_class.available? }

    it "exposes the MuPDF version it was built against" do
      expect(described_class.mupdf_version).to be_a(String)
    end

    it "renders through MuPDF" do
      pdf = PDFBuilder.single_page(text: "Native render")
      pix = described_class.render(data: pdf, number: 0, matrix: RUDF::Matrix.scale(1, 1))
      expect(pix).to be_a(RUDF::Pixmap)
      expect(pix.width).to be > 0
    end
  end
end
