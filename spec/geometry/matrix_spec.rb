# frozen_string_literal: true

require "spec_helper"

RSpec.describe RUDF::Matrix do
  it "defaults to the zero matrix" do
    expect(described_class.new.to_a).to eq([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
  end

  it "builds a scaling matrix from two numbers" do
    expect(described_class.new(2, 3).to_a).to eq([2.0, 0.0, 0.0, 3.0, 0.0, 0.0])
  end

  it "builds a rotation matrix from one number" do
    m = described_class.new(90)
    expect(m.a).to be_within(1e-9).of(0.0)
    expect(m.b).to be_within(1e-9).of(1.0)
    expect(m.c).to be_within(1e-9).of(-1.0)
    expect(m.d).to be_within(1e-9).of(0.0)
  end

  it "exposes an identity constant" do
    expect(RUDF::IDENTITY).to eq(described_class.identity)
    expect(RUDF::IDENTITY).to be_identity
  end

  it "concatenates via multiplication" do
    scale = described_class.scale(2, 2)
    translate = described_class.translate(10, 0)
    combined = scale * translate
    point = RUDF::Point.new(1, 1).transform(combined)
    expect(point).to eq(RUDF::Point.new(12, 2))
  end

  it "inverts a matrix" do
    m = described_class.new(2, 0, 0, 4, 5, 6)
    inv = m.inverse
    expect((m * inv)).to eq(described_class.identity)
  end

  it "raises when inverting a singular matrix" do
    expect { described_class.new.inverse }.to raise_error(RUDF::Error)
  end

  it "pre-translates in place" do
    m = described_class.identity.pre_translate(3, 4)
    expect(m.e).to eq(3.0)
    expect(m.f).to eq(4.0)
  end

  it "pre-rotates by 90 degrees exactly" do
    m = described_class.identity.pre_rotate(90)
    expect(m.to_a).to eq([0.0, 1.0, -1.0, 0.0, 0.0, 0.0])
  end
end
