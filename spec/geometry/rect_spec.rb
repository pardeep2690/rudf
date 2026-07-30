# frozen_string_literal: true

require "spec_helper"

RSpec.describe RUDF::Rect do
  subject(:rect) { described_class.new(0, 0, 100, 50) }

  it "computes width and height" do
    expect(rect.width).to eq(100.0)
    expect(rect.height).to eq(50.0)
  end

  it "exposes corner points" do
    expect(rect.top_left).to eq(RUDF::Point.new(0, 0))
    expect(rect.bottom_right).to eq(RUDF::Point.new(100, 50))
  end

  it "reports emptiness and validity" do
    expect(rect).not_to be_empty
    expect(described_class.new(10, 10, 10, 20)).to be_empty
    expect(described_class.new(20, 0, 0, 20)).not_to be_valid
  end

  it "normalizes reversed corners" do
    r = described_class.new(100, 50, 0, 0).normalize
    expect(r.to_a).to eq([0.0, 0.0, 100.0, 50.0])
  end

  it "tests point and rect containment" do
    expect(rect.contains?(RUDF::Point.new(10, 10))).to be(true)
    expect(rect.contains?([200, 200])).to be(false)
    expect(rect.contains?(described_class.new(10, 10, 20, 20))).to be(true)
  end

  it "computes intersection and union" do
    other = described_class.new(50, 25, 150, 75)
    expect((rect & other).to_a).to eq([50.0, 25.0, 100.0, 50.0])
    expect((rect | other).to_a).to eq([0.0, 0.0, 150.0, 75.0])
  end

  it "grows to include a point" do
    r = described_class.new(0, 0, 10, 10).include_point([20, 5])
    expect(r.to_a).to eq([0.0, 0.0, 20.0, 10.0])
  end

  it "rounds to an integer rect" do
    r = described_class.new(0.2, 0.8, 10.1, 10.9).round
    expect(r).to be_a(RUDF::IRect)
    expect(r.to_a).to eq([0, 0, 11, 11])
  end

  it "transforms by a matrix" do
    r = described_class.new(0, 0, 10, 10).transform(RUDF::Matrix.scale(2, 3))
    expect(r.to_a).to eq([0.0, 0.0, 20.0, 30.0])
  end
end
