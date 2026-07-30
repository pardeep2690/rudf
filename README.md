# RUDF — Ruby PDF

**RUDF** ("Ruby PDF") is a pure-Ruby port of the excellent
[PyMuPDF](https://github.com/pymupdf/PyMuPDF) (`fitz`) library. It brings
PyMuPDF's document model and geometry API to Ruby, backed by a self-contained
PDF parser — **no native extensions and no runtime dependencies**.

> PyMuPDF is a thin Python binding over the native [MuPDF](https://mupdf.com/)
> C engine. RUDF ports the parts of that API that translate cleanly into pure
> Ruby: the document/page model and the geometry primitives, on top of an
> original PDF parser. Rendering (rasterizing pages to images), which relies on
> MuPDF's C renderer, is intentionally out of scope for this pure-Ruby core —
> see [Roadmap](#roadmap).

## Features

- Open PDFs from a file path or an in-memory byte string.
- Read document metadata (title, author, producer, dates, …).
- Enumerate pages; the document is `Enumerable`.
- Inspect page geometry: media box, crop box, rotation, and the
  rotation-aware page rectangle.
- Extract visible text from page content streams.
- A robust parser that handles classic cross-reference tables, cross-reference
  **streams**, and **object streams** (PDF 1.5+), plus `FlateDecode`,
  `ASCIIHexDecode` and `ASCII85Decode` filters.
- Faithful ports of `fitz`'s geometry types: `Point`, `Matrix`, `Rect`,
  `IRect`, and `Quad`.

## Installation

Add it to your `Gemfile`:

```ruby
gem "rudf"
```

Or install directly:

```sh
gem install rudf
```

RUDF targets Ruby 3.0+ and depends only on the standard library (`zlib`,
`stringio`).

## Quick start

```ruby
require "rudf"

# Block form closes the document automatically.
RUDF.open("report.pdf") do |doc|
  puts "Pages: #{doc.page_count}"
  puts "Title: #{doc.metadata['title']}"

  doc.each_page do |page|
    puts "--- page #{page.number} (#{page.rect}) ---"
    puts page.get_text
  end
end

# Or manage the lifecycle yourself:
doc = RUDF.open("report.pdf")
first = doc[0]
puts first.rotation      # => 0, 90, 180 or 270
puts first.mediabox      # => Rect(0, 0, 595, 842)
doc.close

# Read from bytes already in memory:
bytes = File.binread("report.pdf")
RUDF.from_bytes(bytes) { |doc| puts doc.page_count }
```

## Geometry

The geometry classes mirror PyMuPDF's semantics, including its constructor
overloads.

```ruby
RUDF::Point.new(3, 4).abs          # => 5.0  (vector length)
RUDF::Point.new(1, 0) * RUDF::Matrix.new(90)   # rotate 90°

RUDF::Matrix.new              # zero matrix (0,0,0,0,0,0)
RUDF::Matrix.new(2, 3)        # scale x by 2, y by 3
RUDF::Matrix.new(30)          # rotate 30 degrees
RUDF::IDENTITY                # the identity matrix, like fitz.Identity

r = RUDF::Rect.new(0, 0, 100, 50)
r.width                       # => 100.0
r.contains?(RUDF::Point.new(10, 10))          # => true
(r & RUDF::Rect.new(50, 25, 150, 75))          # intersection
r.transform(RUDF::Matrix.scale(2, 2)).round    # => IRect(0, 0, 200, 100)
```

## Mapping from PyMuPDF

| PyMuPDF (`fitz`)                | RUDF                                  |
| ------------------------------- | ------------------------------------- |
| `fitz.open(path)`               | `RUDF.open(path)`                     |
| `fitz.open(stream=bytes)`       | `RUDF.open(nil, stream: bytes)` / `RUDF.from_bytes(bytes)` |
| `doc.page_count`                | `doc.page_count`                      |
| `doc.load_page(n)` / `doc[n]`   | `doc.load_page(n)` / `doc[n]`         |
| `doc.metadata`                  | `doc.metadata`                        |
| `for page in doc:`              | `doc.each_page { |page| ... }`        |
| `page.rect` / `page.bound()`    | `page.rect` / `page.bound`            |
| `page.mediabox`                 | `page.mediabox`                       |
| `page.rotation`                 | `page.rotation`                       |
| `page.get_text()`               | `page.get_text`                       |
| `fitz.Point`, `fitz.Matrix`, …  | `RUDF::Point`, `RUDF::Matrix`, …       |
| `fitz.Identity`                 | `RUDF::IDENTITY`                      |

## Design notes

- **Parsing strategy.** Rather than trusting a possibly-broken cross-reference
  table, RUDF scans the whole file for `N G obj` markers to build its object
  index, then expands any object streams it finds. This tolerates damaged
  xref sections and handles both classic and PDF 1.5+ compressed layouts
  uniformly.
- **Text extraction.** `get_text` interprets the text-showing operators
  (`Tj`, `TJ`, `'`, `"`) and the positioning operators (`Td`, `TD`, `T*`) to
  recover text with reasonable line structure. Bytes are decoded as
  Latin-1/PDFDoc text, which is correct for the common case of standard fonts;
  full font/CMap-driven decoding is on the roadmap.

## Roadmap

Contributions welcome. Planned, in rough priority order:

- Font/CMap-aware text decoding and `"dict"`/`"words"`/`"blocks"` extraction
  modes.
- Encrypted-document support (RC4/AES).
- Links, annotations, and the document outline (table of contents).
- Image extraction.
- Optional native rendering via MuPDF FFI bindings for `get_pixmap`.

## Development

```sh
bundle install
bundle exec rspec      # run the test suite
```

## License

Released under the [MIT License](LICENSE).

RUDF is an independent reimplementation inspired by PyMuPDF's API. It is not
affiliated with or endorsed by Artifex Software or the PyMuPDF project. MuPDF
and PyMuPDF are distributed under the GNU AGPL / commercial licenses; RUDF
shares **no source code** with them and is a clean-room port of the public API
surface only.
