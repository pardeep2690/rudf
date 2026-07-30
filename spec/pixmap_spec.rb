# frozen_string_literal: true

require "spec_helper"
require "zlib"
require "tempfile"

RSpec.describe RUDF::Pixmap do
  # 2x2 RGB: red, green / blue, white.
  let(:samples) { [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255].pack("C*") }
  subject(:pixmap) { described_class.new(width: 2, height: 2, n: 3, samples: samples) }

  it "exposes dimensions and colorspace" do
    expect(pixmap.width).to eq(2)
    expect(pixmap.height).to eq(2)
    expect(pixmap.n).to eq(3)
    expect(pixmap.colorspace).to eq("DeviceRGB")
    expect(pixmap).not_to be_alpha
  end

  it "reads individual pixels" do
    expect(pixmap.pixel(0, 0)).to eq([255, 0, 0])
    expect(pixmap.pixel(1, 1)).to eq([255, 255, 255])
  end

  it "raises for out-of-range pixels" do
    expect { pixmap.pixel(5, 5) }.to raise_error(ArgumentError)
  end

  it "encodes to a valid PNG with correct dimensions" do
    png = pixmap.to_png
    expect(png[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)
    expect(png.byteslice(16, 8).unpack("N2")).to eq([2, 2])
  end

  it "saves to a .png file" do
    Tempfile.create(["pix", ".png"]) do |f|
      pixmap.save(f.path)
      expect(::File.binread(f.path)[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)
    end
  end

  it "rejects non-png output formats" do
    expect { pixmap.save("/tmp/x.bmp") }.to raise_error(RUDF::Error)
  end

  it "marks RGBA pixmaps as having alpha" do
    rgba = described_class.new(width: 1, height: 1, n: 4, samples: "\xFF\x00\x00\x80".b)
    expect(rgba).to be_alpha
  end
end
