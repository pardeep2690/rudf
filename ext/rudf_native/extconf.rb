# frozen_string_literal: true

require "mkmf"

# The native MuPDF backend is optional. If MuPDF's headers and library are not
# found, we emit a no-op Makefile so that `gem install rudf` still succeeds and
# the gem runs in pure-Ruby mode. Precompiled platform gems ship the compiled
# extension so end users need nothing installed.

# Allow --with-mupdf-dir=/path (adds /path/include and /path/lib).
dir_config("mupdf")

def mupdf_available?
  header = have_header("mupdf/fitz.h")
  return false unless header

  # Try pkg-config first, then fall back to explicit libraries.
  if pkg_config("mupdf") && have_func("fz_new_context_imp")
    return true
  end

  found = have_library("mupdf", "fz_new_context_imp")
  # MuPDF's third-party dependencies (may be folded into libmupdf on some
  # distributions, hence "optional").
  have_library("mupdf-third")
  have_library("z")
  have_library("m")
  found
end

if mupdf_available?
  # Reasonable warning flags; keep it quiet by default.
  $CFLAGS << " -std=c11"
  create_makefile("rudf/rudf_native")
else
  warn <<~MSG
    [rudf] MuPDF not found — building without the native backend.
           The gem will work in pure-Ruby mode; `get_pixmap` and other native
           features will raise until MuPDF is installed and the gem reinstalled
           (or a precompiled platform gem is used).
           Point at a custom install with:  gem install rudf -- --with-mupdf-dir=/path
  MSG
  File.write("Makefile", <<~MAKE)
    all:
    \t@true
    install:
    \t@true
    clean:
    \t@true
  MAKE
end
