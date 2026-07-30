# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Font-aware text extraction: `/ToUnicode` CMap decoding, `/Encoding`
  (WinAnsi/MacRoman) with `/Differences`, and Type0/Identity-H composite
  fonts.
- A `PDF::TextPage` engine that interprets the content stream into
  blocks/lines/spans with bounding boxes.
- New `Page#get_text` modes: `"words"`, `"blocks"`, and `"dict"`, with
  coordinates using a top-left origin to match PyMuPDF. `Page#text_page`
  exposes the structured result.

## [0.1.0] - 2026-07-30

Initial release: a pure-Ruby port of the PyMuPDF (`fitz`) API.

### Added

- `RUDF.open` / `RUDF.from_bytes` entry points, with an auto-closing block
  form.
- `RUDF::Document`: `page_count`, `load_page` / `[]`, `each_page`, `metadata`,
  `close`, and `Enumerable` support.
- `RUDF::Page`: `rect` / `bound`, `mediabox`, `cropbox`, `rotation`,
  `contents`, and `get_text`.
- Geometry primitives ported from `fitz`: `Point`, `Matrix`, `Rect`, `IRect`,
  `Quad`, and the `IDENTITY` matrix constant.
- A self-contained PDF parser supporting classic cross-reference tables,
  cross-reference streams, and object streams (PDF 1.5+).
- Stream filters: `FlateDecode` (with PNG predictors), `ASCIIHexDecode`, and
  `ASCII85Decode`.
- RSpec test suite covering geometry, parsing, and the document API.

[Unreleased]: https://github.com/pardeep2690/rudf/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/pardeep2690/rudf/releases/tag/v0.1.0
