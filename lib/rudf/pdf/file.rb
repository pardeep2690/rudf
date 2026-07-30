# frozen_string_literal: true

require_relative "lexer"
require_relative "parser"
require_relative "object"
require_relative "filters"
require_relative "crypto"

module RUDF
  module PDF
    # A parsed PDF file: the low-level object store behind {RUDF::Document}.
    #
    # Objects are located with a whole-file scan for +N G obj+ markers, which
    # is robust against damaged cross-reference tables. Compressed objects held
    # inside object streams (PDF 1.5+) are expanded on load, so both classic
    # and modern documents resolve uniformly through {#resolve} / {#object}.
    class File
      OBJ_MARKER = /(?<num>\d+)\s+(?<gen>\d+)\s+obj\b/.freeze

      attr_reader :version

      # The raw file bytes (used by the optional rendering backend).
      def raw_bytes
        @data
      end

      def initialize(data)
        @data = data.b # treat as binary
        @cache = {}
        @compressed = {} # object number => decoded value (from ObjStm)
        @offsets = {}     # object number => byte offset
        @decryptor = nil
        @parser = Parser.new(@data, resolver: method(:resolve))
        detect_version
        raise FileDataError, "not a PDF file (missing %PDF header)" unless @version

        build_offset_table
        # Order matters for encrypted files: find the trailer (and the
        # unencrypted /Encrypt dict), install decryption, THEN parse content.
        locate_trailer
        setup_encryption
        expand_object_streams
      end

      # The document catalog (the +/Root+ object).
      def catalog
        @catalog ||= resolve(@root_ref) || find_catalog_by_scan
      end

      # The document information dictionary (+/Info+), or +nil+.
      def info
        return @info if defined?(@info)

        @info = @info_ref ? resolve(@info_ref) : nil
      end

      # Resolve a value: follow a {Reference}, otherwise return it unchanged.
      def resolve(value)
        return value unless value.is_a?(Reference)

        object(value.number)
      end

      # Fetch object +number+, resolving from the offset table or an object
      # stream, with memoization.
      def object(number)
        return @cache[number] if @cache.key?(number)

        value =
          if @compressed.key?(number)
            @compressed[number]
          elsif @offsets.key?(number)
            @parser.parse_indirect_object(@offsets[number])
          end
        @cache[number] = value
      end

      # Convenience: resolve +value+ and dereference dictionary key +key+.
      def dict_get(dict, key)
        dict = resolve(dict)
        return nil unless dict.is_a?(Hash)

        resolve(dict[key])
      end

      # True when the document was opened from an encrypted file.
      def encrypted?
        !@encrypt_ref.nil?
      end

      # The highest object number seen in the file (for allocating new ones).
      def max_object_number
        (@offsets.keys + @compressed.keys).max || 0
      end

      # The +/Root+ reference, used when writing an incremental trailer.
      def root_reference
        @root_ref
      end

      private

      def detect_version
        header = @data.byteslice(0, 1024).to_s
        @version = header[/%PDF-(\d+\.\d+)/, 1]
      end

      def build_offset_table
        @data.to_enum(:scan, OBJ_MARKER).each do
          match = Regexp.last_match
          num = match[:num].to_i
          # Later definitions (incremental updates) override earlier ones.
          @offsets[num] = match.begin(0)
        end
      end

      # Decode every /Type /ObjStm stream and register the objects it holds.
      def expand_object_streams
        @offsets.each_key do |num|
          value = @parser.parse_indirect_object(@offsets[num])
          @cache[num] = value
          next unless value.is_a?(Stream)

          dict = value.dict
          type = dict["Type"]
          next unless type.is_a?(Name) && type.value == "ObjStm"

          expand_object_stream(value)
        rescue ParseError
          next
        end
      end

      def expand_object_stream(stream)
        count = resolve(stream.dict["N"]).to_i
        first = resolve(stream.dict["First"]).to_i
        payload = stream.decoded

        header_lexer = Lexer.new(payload, 0)
        entries = []
        count.times do
          onum = header_lexer.next_token
          off = header_lexer.next_token
          break unless onum.type == :number && off.type == :number

          entries << [onum.value, off.value]
        end

        entries.each do |onum, off|
          # Do not overwrite a directly-stored (newer) object definition.
          next if @offsets.key?(onum)

          obj_parser = Parser.new(payload, lexer: Lexer.new(payload, first + off), resolver: method(:resolve))
          @compressed[onum] = obj_parser.parse_object
        rescue ParseError
          next
        end
      end

      def locate_trailer
        @root_ref = nil
        @info_ref = nil
        @encrypt_ref = nil
        @id_array = nil

        collect_classic_trailers
        collect_xref_stream_trailers
      end

      def collect_classic_trailers
        pos = 0
        while (idx = @data.index("trailer", pos))
          lexer = Lexer.new(@data, idx + "trailer".length)
          token = lexer.next_token
          if token.type == :dict_open
            dict = Parser.new(@data, lexer: lexer, resolver: method(:resolve)).send(:parse_dictionary)
            apply_trailer(dict)
          end
          pos = idx + "trailer".length
        end
      end

      # Cross-reference streams (PDF 1.5+) carry the trailer keys in their dict.
      # Parsed here without decryption (xref streams are never encrypted) and
      # not cached, so encrypted content objects are not stored in cleartext.
      def collect_xref_stream_trailers
        @offsets.each_key do |num|
          value = @parser.parse_indirect_object(@offsets[num])
          next unless value.is_a?(Stream)

          type = value.dict["Type"]
          apply_trailer(value.dict) if type.is_a?(Name) && type.value == "XRef"
        rescue ParseError
          next
        end
      end

      def apply_trailer(dict)
        @root_ref = dict["Root"] if dict["Root"]
        @info_ref = dict["Info"] if dict["Info"]
        @encrypt_ref = dict["Encrypt"] if dict["Encrypt"]
        @id_array = dict["ID"] if dict["ID"]
      end

      # Build the decryption handler from the (unencrypted) /Encrypt dict, then
      # switch the parser over to a decrypting one for all subsequent objects.
      def setup_encryption
        return unless @encrypt_ref

        encrypt = parse_ref_without_decryption(@encrypt_ref)
        raise EncryptedError, "malformed /Encrypt dictionary" unless encrypt.is_a?(Hash)

        filter = encrypt["Filter"]
        unless filter.is_a?(Name) && filter.value == "Standard"
          raise EncryptedError, "unsupported security handler: #{filter.inspect}"
        end

        @crypto = Crypto.new(encrypt, first_file_id, method(:resolve))
        @decryptor = @crypto.method(:decrypt)
        @parser = Parser.new(@data, resolver: method(:resolve), decryptor: @decryptor)
      end

      def parse_ref_without_decryption(ref)
        return ref unless ref.is_a?(Reference)

        offset = @offsets[ref.number]
        offset ? @parser.parse_indirect_object(offset) : nil
      end

      def first_file_id
        arr = @id_array
        arr = @parser.parse_indirect_object(@offsets[arr.number]) if arr.is_a?(Reference) && @offsets[arr.number]
        arr.is_a?(Array) && arr[0].is_a?(String) ? arr[0] : nil
      end

      # Fallback used if no trailer/Root was found: look for a /Type /Catalog.
      def find_catalog_by_scan
        @offsets.each_key do |num|
          value = object(num)
          return value if value.is_a?(Hash) &&
                          value["Type"].is_a?(Name) && value["Type"].value == "Catalog"
        end
        nil
      end
    end
  end
end
