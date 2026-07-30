# frozen_string_literal: true

module RUDF
  module PDF
    # Maps PostScript/Adobe glyph names to Unicode code points.
    #
    # A full Adobe Glyph List has thousands of entries; the majority of real
    # documents only ever reference a small common subset via +/Differences+,
    # so a curated table plus the algorithmic +uniXXXX+ / +uXXXXXX+ forms
    # covers the overwhelming common case. Unknown names fall back to +nil+ so
    # callers can degrade gracefully.
    module GlyphList
      # Latin letters and digits map to themselves and are handled without a
      # table; this covers punctuation, ligatures and symbols.
      COMMON = {
        "space" => 0x20, "exclam" => 0x21, "quotedbl" => 0x22,
        "numbersign" => 0x23, "dollar" => 0x24, "percent" => 0x25,
        "ampersand" => 0x26, "quotesingle" => 0x27, "parenleft" => 0x28,
        "parenright" => 0x29, "asterisk" => 0x2A, "plus" => 0x2B,
        "comma" => 0x2C, "hyphen" => 0x2D, "period" => 0x2E, "slash" => 0x2F,
        "colon" => 0x3A, "semicolon" => 0x3B, "less" => 0x3C, "equal" => 0x3D,
        "greater" => 0x3E, "question" => 0x3F, "at" => 0x40,
        "bracketleft" => 0x5B, "backslash" => 0x5C, "bracketright" => 0x5D,
        "asciicircum" => 0x5E, "underscore" => 0x5F, "grave" => 0x60,
        "braceleft" => 0x7B, "bar" => 0x7C, "braceright" => 0x7D,
        "asciitilde" => 0x7E,
        # Common typographic punctuation.
        "quoteleft" => 0x2018, "quoteright" => 0x2019,
        "quotedblleft" => 0x201C, "quotedblright" => 0x201D,
        "bullet" => 0x2022, "endash" => 0x2013, "emdash" => 0x2014,
        "ellipsis" => 0x2026, "dagger" => 0x2020, "daggerdbl" => 0x2021,
        "perthousand" => 0x2030, "guilsinglleft" => 0x2039,
        "guilsinglright" => 0x203A, "trademark" => 0x2122,
        "fi" => 0xFB01, "fl" => 0xFB02, "florin" => 0x0192,
        "minus" => 0x2212, "fraction" => 0x2044,
        # Currency and symbols.
        "Euro" => 0x20AC, "cent" => 0xA2, "sterling" => 0xA3, "yen" => 0xA5,
        "copyright" => 0xA9, "registered" => 0xAE, "degree" => 0xB0,
        "plusminus" => 0xB1, "paragraph" => 0xB6, "section" => 0xA7,
        "middot" => 0xB7, "multiply" => 0xD7, "divide" => 0xF7,
        # Accented letters commonly seen via Differences.
        "adieresis" => 0xE4, "odieresis" => 0xF6, "udieresis" => 0xFC,
        "Adieresis" => 0xC4, "Odieresis" => 0xD6, "Udieresis" => 0xDC,
        "germandbls" => 0xDF, "eacute" => 0xE9, "egrave" => 0xE8,
        "agrave" => 0xE0, "ccedilla" => 0xE7, "ntilde" => 0xF1,
        "aacute" => 0xE1, "iacute" => 0xED, "oacute" => 0xF3,
        "uacute" => 0xFA, "ocircumflex" => 0xF4, "acircumflex" => 0xE2
      }.freeze

      module_function

      # Return the Unicode code point for +name+, or +nil+ if unknown.
      def to_unicode(name)
        return nil if name.nil? || name.empty?
        return COMMON[name] if COMMON.key?(name)

        # Single Latin letter/digit glyph names map to themselves.
        return name.ord if name.length == 1

        # Algorithmic forms defined by the Adobe glyph-naming convention.
        if (m = name.match(/\Auni([0-9A-Fa-f]{4})\z/))
          return m[1].to_i(16)
        end
        if (m = name.match(/\Au([0-9A-Fa-f]{4,6})\z/))
          return m[1].to_i(16)
        end
        # gNN / cidNN and similar are font-specific; no Unicode is derivable.
        nil
      end

      # Return the code point as a UTF-8 String, or +nil+.
      def to_char(name)
        cp = to_unicode(name)
        cp ? [cp].pack("U") : nil
      end
    end
  end
end
