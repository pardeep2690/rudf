# frozen_string_literal: true

module RUDF
  module PDF
    # Metrics for the PDF "standard 14" fonts, used when writing text so that
    # line widths can be measured for alignment and centering.
    #
    # Glyph widths come from the Adobe Font Metrics for the WinAnsi character
    # range (codes 32-126, which covers ordinary text). Only the families
    # needed for typical output are tabulated precisely; others fall back to
    # Helvetica metrics.
    class StandardFont
      # PyMuPDF-style short aliases mapped to the base font name.
      ALIASES = {
        "helv" => "Helvetica", "heit" => "Helvetica-Oblique",
        "hebo" => "Helvetica-Bold", "hebi" => "Helvetica-BoldOblique",
        "cour" => "Courier", "cobo" => "Courier-Bold",
        "coit" => "Courier-Oblique", "cobi" => "Courier-BoldOblique",
        "tiro" => "Times-Roman", "tibo" => "Times-Bold",
        "tiit" => "Times-Italic", "tibi" => "Times-BoldItalic",
        "symb" => "Symbol", "zadb" => "ZapfDingbats"
      }.freeze

      # Widths for codes 32..126, per 1000 units of text space.
      HELVETICA = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333,
        278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278,
        584, 584, 584, 556, 1015, 667, 667, 722, 722, 667, 611, 778, 722, 278,
        500, 667, 556, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944,
        667, 667, 611, 278, 278, 278, 469, 556, 333, 556, 556, 500, 556, 556,
        278, 556, 556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500,
        278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584
      ].freeze

      HELVETICA_BOLD = [
        278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333,
        278, 278, 556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333,
        584, 584, 584, 611, 975, 722, 722, 722, 722, 667, 611, 778, 722, 278,
        556, 722, 611, 833, 722, 778, 667, 778, 722, 667, 611, 722, 667, 944,
        667, 667, 611, 333, 278, 333, 584, 556, 333, 556, 611, 556, 611, 556,
        333, 611, 611, 278, 278, 556, 278, 889, 611, 611, 611, 611, 389, 556,
        333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584
      ].freeze

      FIRST_CODE = 32

      def initialize(name)
        @base = self.class.resolve_name(name)
        @widths = width_table(@base)
        @default = @base.start_with?("Courier") ? 600 : 556
      end

      attr_reader :base

      # Resolve an alias or free-form name to a canonical base font name.
      def self.resolve_name(name)
        n = name.to_s
        ALIASES[n.downcase] || n
      end

      def bold?
        @base.include?("Bold")
      end

      # Width of a single character (by code point), per 1000 units.
      def char_width(codepoint)
        idx = codepoint - FIRST_CODE
        if @widths && idx >= 0 && idx < @widths.length
          @widths[idx]
        else
          @default
        end
      end

      # Width in text-space units of +string+ rendered at +size+.
      def text_width(string, size)
        total = string.each_char.sum { |ch| char_width(ch.ord) }
        total / 1000.0 * size
      end

      private

      def width_table(base)
        case base
        when "Helvetica", "Helvetica-Oblique" then HELVETICA
        when "Helvetica-Bold", "Helvetica-BoldOblique" then HELVETICA_BOLD
        when /\ACourier/ then nil # constant 600
        else HELVETICA # reasonable fallback for Times/Symbol/etc.
        end
      end
    end
  end
end
