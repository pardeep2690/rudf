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
- **Transparent decryption** of encrypted documents (empty user password):
  RC4, AES-128 and AES-256.
- Read document metadata (title, author, producer, dates, …).
- Enumerate pages; the document is `Enumerable`.
- Inspect page geometry: media box, crop box, rotation, and the
  rotation-aware page rectangle.
- **Font-aware text extraction** with `/ToUnicode` CMaps and `/Encoding`
  handling, in `text`, `words`, `blocks` and `dict` modes (with bounding
  boxes, top-left origin like PyMuPDF).
- **Navigation**: table of contents (`get_toc`), links (`get_links`) and
  annotations (`annots`).
- **Image extraction**: list page images and export them (JPEG passthrough or
  synthesised PNG).
- **Optional native rendering** (`get_pixmap`) via a MuPDF FFI backend, loaded
  only if present — the core stays dependency-free.
- **Write text**: create new PDFs (`RUDF::Writer`) or stamp text onto existing
  pages (`Document#insert_textbox` + `save`), with alignment, centering and
  bold via the standard fonts.
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
| `page.get_text(mode)`           | `page.get_text(mode)` (`text`/`words`/`blocks`/`dict`) |
| `doc.get_toc()`                 | `doc.get_toc`                         |
| `page.get_links()`              | `page.get_links` / `page.links`       |
| `page.annots()`                 | `page.annots`                         |
| `page.get_images()`             | `page.get_images`                     |
| `doc.extract_image(xref)`       | `doc.extract_image(xref)`             |
| `page.get_pixmap()`             | `page.get_pixmap` (optional backend)  |
| `fitz.Point`, `fitz.Matrix`, …  | `RUDF::Point`, `RUDF::Matrix`, …       |
| `fitz.Identity`                 | `RUDF::IDENTITY`                      |

## Design notes

- **Parsing strategy.** Rather than trusting a possibly-broken cross-reference
  table, RUDF scans the whole file for `N G obj` markers to build its object
  index, then expands any object streams it finds. This tolerates damaged
  xref sections and handles both classic and PDF 1.5+ compressed layouts
  uniformly.
- **Text extraction.** A `TextPage` interpreter tracks the PDF text and
  graphics state (text/line matrices, font, spacing, the CTM) to place each
  glyph, then groups glyphs into words, lines and blocks. Character codes are
  decoded through the font's `/ToUnicode` CMap when present, falling back to
  its `/Encoding` (WinAnsi/MacRoman + `/Differences`); Type0/Identity-H
  composite fonts are supported. All `get_text` modes derive from this single
  structure, as in PyMuPDF.
- **Decryption.** The standard security handler derives the file key from the
  `/Encrypt` dictionary and decrypts strings and streams per object as they
  are parsed, so encrypted documents open transparently.

## Writing text

RUDF can create PDFs and stamp text onto existing ones. Text is measured with
the standard-14 font metrics, so alignment and centering are accurate. Use a
bold base font (e.g. `Helvetica-Bold`, alias `hebo`) for bold text.

### Bold text centered around a point, within a height band

The key idea: `insert_textbox` centers text **horizontally** inside its box and
**vertically** within the box's height. So to center around a point `cx` and
between two heights `top` and `bottom`, make the box symmetric about `cx` and
span `top..bottom`:

```ruby
require "rudf"

cx     = 300           # the horizontal center you want the text around
top    = 150           # top of the height band  (top-left origin, y grows down)
bottom = 210           # bottom of the height band
half_w = 250           # half-width of the box (just needs to be wide enough)

writer = RUDF::Writer.new
page   = writer.add_page(width: 600, height: 800)

page.insert_textbox(
  [cx - half_w, top, cx + half_w, bottom], # box symmetric about cx, spanning the band
  "BOLD & CENTERED",
  fontname: "Helvetica-Bold",              # bold
  fontsize: 28,
  align:  :center,                         # horizontal: centered on cx
  valign: :center                          # vertical: centered in top..bottom
)

writer.save("centered.pdf")
```

The text's horizontal center lands on `cx` and its vertical center on
`(top + bottom) / 2`. Coordinates use a **top-left origin** (y increases
downward), the same convention as text extraction and links.

### Stamping onto an existing PDF

`Document#insert_textbox` draws onto a page of an already-open document;
`Document#save` writes an incremental update that appends the new content and
leaves the original bytes intact.

```ruby
RUDF.open("invoice.pdf") do |doc|
  page_h = doc[0].mediabox.height
  doc.insert_textbox(
    0,                                   # page index
    [0, 40, doc[0].mediabox.width, 90],  # full-width band near the top
    "PAID",
    fontname: "Helvetica-Bold", fontsize: 32, align: :center, color: [0.8, 0, 0]
  )
  doc.save("invoice-stamped.pdf")
end
```

### Other helpers

```ruby
# A single line with its baseline at a point (top-left origin):
page.insert_text([72, 72], "Header", fontsize: 14, fontname: "hebo")

# Measure a string yourself, e.g. to center manually:
font = RUDF::PDF::StandardFont.new("Helvetica-Bold")
w = font.text_width("My title", 24)      # width in points at 24pt
```

Notes and current limits: only the standard-14 fonts are available for
writing (no embedding yet); text is WinAnsi-encoded; editing an **encrypted**
document is refused. Multi-line text wraps to the box width and each line is
aligned independently.

## Page rendering (optional)

Rendering a page to a raster needs a native engine, so it is opt-in. If the
[`ffi`](https://rubygems.org/gems/ffi) gem and the MuPDF shared library are
both present, `get_pixmap` works; otherwise it raises
`RUDF::RenderingUnavailableError` and the rest of the library is unaffected.

```ruby
if RUDF::Render.available?
  RUDF.open("report.pdf") do |doc|
    pix = doc[0].get_pixmap(dpi: 150)   # => RUDF::Pixmap
    pix.save("page0.png")
  end
end
```

Set `RUDF_MUPDF_VERSION` if your installed MuPDF reports a version other than
the default the backend expects.

## Roadmap

The original roadmap (font-aware text, encryption, navigation, image
extraction, optional rendering) is now implemented. Contributions welcome for:

- `rawdict`/`html`/`xml` text output and better word/line segmentation.
- Public-key and password-protected encryption (non-empty user passwords).
- Writing: embedded/custom fonts, shapes and images, and editing existing
  content (text insertion is implemented).
- A pure-Ruby rasteriser so `get_pixmap` needs no native library.
- CCITT/JBIG2 image decoding (currently passed through).

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
