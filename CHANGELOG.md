# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Write support: `RUDF::Writer` builds new PDFs and draws text
  (`insert_text`, `insert_textbox` with horizontal alignment and vertical
  centering within a box). `Document#insert_text`/`#insert_textbox` +
  `Document#save` stamp text onto existing pages via an incremental update.
- Standard-14 font metrics (`PDF::StandardFont`) for measuring text, used by
  the writer for alignment/centering and by the reader as a `/Widths`
  fallback so positioning is accurate for non-embedded base fonts.
- Bold text via the `Helvetica-Bold` base font (and PyMuPDF-style aliases
  such as `hebo`).

### Earlier in this cycle

- Font-aware text extraction: `/ToUnicode` CMap decoding, `/Encoding`
  (WinAnsi/MacRoman) with `/Differences`, and Type0/Identity-H composite
  fonts.
- A `PDF::TextPage` engine that interprets the content stream into
  blocks/lines/spans with bounding boxes.
- New `Page#get_text` modes: `"words"`, `"blocks"`, and `"dict"`, with
  coordinates using a top-left origin to match PyMuPDF. `Page#text_page`
  exposes the structured result.
- Transparent decryption of encrypted documents (empty user password) via the
  standard security handler: RC4 (V1/V2), AES-128 (V4/AESV2) and AES-256
  (V5/AESV3, revisions 5 and 6). `Document#encrypted?` reports the state.
- Document navigation: `Document#get_toc` builds the table of contents from
  the outline tree (with named/explicit destination resolution); `Page#links`
  returns GoTo/URI/remote links; `Page#annots` returns `Annotation` objects.
- Image extraction: `Page#get_images` lists image XObjects (recursing into
  form XObjects); `Document#extract_image` returns JPEG/JPEG2000 passthrough
  or a PNG synthesised from raw samples (CMYK and indexed colour → RGB).
- Optional native page rendering: `Page#get_pixmap` returns a `Pixmap` via a
  lazily-loaded MuPDF FFI backend. The pure-Ruby core needs no native
  dependency; when none is present a clear `RenderingUnavailableError` is
  raised. `Pixmap` (pure Ruby) reads pixels and encodes/saves PNG, and
  `RUDF::Render.available?` reports capability.

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
