# frozen_string_literal: true

require "spec_helper"

RSpec.describe RUDF::Point do
  it "builds from two coordinates" do
    p = described_class.new(1, 2)
    expect(p.x).to eq(1.0)
    expect(p.y).to eq(2.0)
  end

  it "copies from another point or array" do
    expect(described_class.new(described_class.new(3, 4))).to eq(described_class.new(3, 4))
    expect(described_class.new([5, 6])).to eq(described_class.new(5, 6))
  end

  it "adds and subtracts componentwise" do
    expect(described_class.new(1, 2) + described_class.new(3, 4)).to eq(described_class.new(4, 6))
    expect(described_class.new(5, 5) - described_class.new(2, 1)).to eq(described_class.new(3, 4))
  end

  it "scales by a scalar" do
    expect(described_class.new(1, 2) * 3).to eq(described_class.new(3, 6))
  end

  it "computes length and distance" do
    expect(described_class.new(3, 4).abs).to eq(5.0)
    expect(described_class.new(0, 0).distance_to([3, 4])).to eq(5.0)
  end

  it "normalizes to a unit vector" do
    unit = described_class.new(3, 4).unit
    expect(unit.abs).to be_within(1e-9).of(1.0)
  end

  it "transforms via a matrix" do
    translated = described_class.new(1, 1).transform(RUDF::Matrix.translate(10, 20))
    expect(translated).to eq(described_class.new(11, 21))
  end

  it "rotates 90 degrees when multiplied by a rotation matrix" do
    rotated = described_class.new(1, 0) * RUDF::Matrix.new(90)
    expect(rotated.x).to be_within(1e-9).of(0.0)
    expect(rotated.y).to be_within(1e-9).of(1.0)
  end
end
