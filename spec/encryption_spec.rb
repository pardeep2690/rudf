# frozen_string_literal: true

require "spec_helper"
require_relative "support/encrypted_pdf_builder"

RSpec.describe "encrypted documents" do
  describe "RC4 (V2/R4)" do
    let(:pdf) { EncryptedPDFBuilder.single_page(text: "Top secret", title: "Eyes Only", method: :rc4) }

    it "opens without raising" do
      expect { RUDF.from_bytes(pdf) { |_| } }.not_to raise_error
    end

    it "decrypts page text" do
      RUDF.from_bytes(pdf) { |doc| expect(doc[0].get_text).to include("Top secret") }
    end

    it "decrypts metadata strings" do
      RUDF.from_bytes(pdf) { |doc| expect(doc.metadata["title"]).to eq("Eyes Only") }
    end

    it "reports the document as encrypted" do
      RUDF.from_bytes(pdf) { |doc| expect(doc.encrypted?).to be(true) }
    end
  end

  describe "AES-128 (AESV2)" do
    let(:pdf) { EncryptedPDFBuilder.single_page(text: "Classified body", title: "Restricted", method: :aes) }

    it "decrypts page text" do
      RUDF.from_bytes(pdf) { |doc| expect(doc[0].get_text).to include("Classified body") }
    end

    it "decrypts metadata strings" do
      RUDF.from_bytes(pdf) { |doc| expect(doc.metadata["title"]).to eq("Restricted") }
    end
  end

  describe "unencrypted documents" do
    it "report as not encrypted" do
      RUDF.from_bytes(PDFBuilder.single_page) { |doc| expect(doc.encrypted?).to be(false) }
    end
  end
end
