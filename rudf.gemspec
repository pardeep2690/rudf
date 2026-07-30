# frozen_string_literal: true

require_relative "lib/rudf/version"

Gem::Specification.new do |spec|
  spec.name = "rudf"
  spec.version = RUDF::VERSION
  spec.authors = ["Pardeep Banssal"]
  spec.email = ["pardeepbanssal@gmail.com"]

  spec.summary = "A pure-Ruby port of PyMuPDF (fitz) for reading and inspecting PDF documents."
  spec.description = <<~DESC
    RUDF ("Ruby PDF") is a dependency-free Ruby port of the PyMuPDF (fitz)
    library. It mirrors PyMuPDF's document model -- Document, Page, and the
    geometry primitives Point, Matrix, Rect, IRect and Quad -- on top of a
    self-contained PDF parser. It supports opening PDFs, reading metadata,
    enumerating pages, inspecting page geometry, and extracting text.
  DESC
  spec.homepage = "https://github.com/pardeep2690/rudf"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]
  spec.bindir = "exe"
  spec.executables = ["rudf"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
