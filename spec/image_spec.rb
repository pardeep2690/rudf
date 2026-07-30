# frozen_string_literal: true

require "spec_helper"
require "zlib"

RSpec.describe "image extraction" do
  let(:pdf) { PDFBuilder.image_doc }

  describe "Page#get_images" do
    it "lists image XObjects with metadata and xref" do
      RUDF.from_bytes(pdf) do |doc|
        images = doc[0].get_images
        expect(images.length).to eq(2)

        flate = images.find { |i| i[:name] == "Im0" }
        expect(flate).to include(width: 2, height: 2, bpc: 8,
                                 colorspace: "DeviceRGB", filter: "FlateDecode")
        expect(flate[:xref]).to eq(6)
      end
    end
  end

  describe "Document#extract_image" do
    it "wraps a FlateDecode raster into a valid PNG" do
      RUDF.from_bytes(pdf) do |doc|
        img = doc.extract_image(6)
        expect(img[:ext]).to eq("png")
        expect(img[:width]).to eq(2)
        expect(img[:image][0, 8]).to eq("\x89PNG\r\n\x1A\n".b)

        # IHDR should report the right dimensions...
        ihdr = img[:image].byteslice(16, 8).unpack("N2")
        expect(ihdr).to eq([2, 2])

        # ...and the pixel data must round-trip back to the original samples.
        idat_start = img[:image].index("IDAT") + 4
        idat = img[:image].byteslice(idat_start, img[:image].bytesize)
        inflated = Zlib::Inflate.inflate(idat[0, idat.bytesize - 12])
        # Strip the per-row filter byte (0) from each 6-byte RGB row.
        pixels = inflated.bytes.each_slice(7).flat_map { |row| row[1..] }.pack("C*")
        expect(pixels).to eq(PDFBuilder::IMAGE_RGB)
      end
    end

    it "passes a DCTDecode image through as JPEG" do
      RUDF.from_bytes(pdf) do |doc|
        img = doc.extract_image(7)
        expect(img[:ext]).to eq("jpg")
        expect(img[:image]).to eq(PDFBuilder::FAKE_JPEG)
      end
    end

    it "raises for a non-image object" do
      RUDF.from_bytes(pdf) do |doc|
        expect { doc.extract_image(1) }.to raise_error(RUDF::Error)
      end
    end
  end
end
