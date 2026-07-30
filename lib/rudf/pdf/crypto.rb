# frozen_string_literal: true

require "digest"
require "openssl"

module RUDF
  module PDF
    # The PDF Standard Security Handler: decrypts strings and streams in an
    # encrypted document.
    #
    # It supports the encryption schemes a reader actually encounters:
    #   * V1/V2  — RC4 (40–128 bit)
    #   * V4     — RC4 or AES-128 (AESV2), selected by the crypt filter
    #   * V5     — AES-256 (AESV3), revisions 5 and 6
    #
    # Only the empty user password is attempted, which opens the common case of
    # documents encrypted merely to set permissions. A document requiring a
    # real open password raises {EncryptedError}.
    class Crypto
      # The 32-byte padding string from the PDF spec (Algorithm 2).
      PAD = [
        0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56,
        0xFF, 0xFA, 0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
        0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A
      ].pack("C*").freeze

      # Build a handler from the +/Encrypt+ dictionary and the file +id+ (the
      # first element of the trailer +/ID+ array). +resolver+ dereferences any
      # indirect values inside the dictionary.
      def initialize(encrypt, id, resolver)
        @resolver = resolver
        @id0 = (id || "").b
        @v = int(res(encrypt["V"])) || 0
        @r = int(res(encrypt["R"])) || 0
        @o = str(res(encrypt["O"]))
        @u = str(res(encrypt["U"]))
        @oe = str(res(encrypt["OE"]))
        @ue = str(res(encrypt["UE"]))
        @p = int(res(encrypt["P"])) || 0
        @length_bytes = (int(res(encrypt["Length"])) || 40) / 8
        meta = res(encrypt["EncryptMetadata"])
        @encrypt_metadata = meta.nil? ? true : meta
        detect_method(encrypt)
        @key = derive_key
      end

      # Decrypt +data+ belonging to object (+num+, +gen+). +kind+ is +:string+
      # or +:stream+ (only relevant for identity/quirk handling).
      def decrypt(data, num, gen, _kind = :string)
        return data if @method == :identity

        case @method
        when :rc4
          rc4(object_key(num, gen, false), data)
        when :aesv2
          aes_cbc_decrypt(object_key(num, gen, true), data)
        when :aesv3
          aes_cbc_decrypt(@key, data)
        else
          data
        end
      end

      private

      def detect_method(encrypt)
        case @v
        when 1, 2
          @method = :rc4
        when 4, 5
          cf = res(encrypt["CF"])
          stmf = res(encrypt["StmF"])
          name = stmf.is_a?(Name) ? stmf.value : "Identity"
          if name == "Identity"
            @method = :identity
          else
            cfm = cf.is_a?(Hash) ? res(res(cf[name])&.fetch("CFM", nil)) : nil
            cfm_name = cfm.is_a?(Name) ? cfm.value : nil
            @method =
              case cfm_name
              when "AESV2" then :aesv2
              when "AESV3" then :aesv3
              when "V2" then :rc4
              else @v == 5 ? :aesv3 : :rc4
              end
            # AES-128 uses a 16-byte key regardless of the /Length hint.
            @length_bytes = 16 if @method == :aesv2
          end
        else
          @method = :rc4
        end
      end

      def derive_key
        return derive_key_v5 if @v == 5

        derive_key_rc4
      end

      # Algorithm 2: compute the file encryption key (empty user password).
      def derive_key_rc4
        md5 = Digest::MD5.new
        md5 << PAD
        md5 << @o[0, 32].to_s
        md5 << [@p].pack("l<")
        md5 << @id0
        md5 << [0xFFFFFFFF].pack("V") if @r >= 4 && !@encrypt_metadata
        key = md5.digest
        if @r >= 3
          50.times { key = Digest::MD5.digest(key[0, @length_bytes]) }
        end
        key[0, @length_bytes]
      end

      # Algorithm 2.A: derive the AES-256 file key from the empty user password.
      def derive_key_v5
        validation_salt = @u[32, 8]
        key_salt = @u[40, 8]
        unless hash_v5("".b, validation_salt) == @u[0, 32]
          raise EncryptedError, "document requires a password (AES-256)"
        end

        intermediate = hash_v5("".b, key_salt)
        cipher = OpenSSL::Cipher.new("aes-256-cbc")
        cipher.decrypt
        cipher.padding = 0
        cipher.key = intermediate
        cipher.iv = ("\x00" * 16).b
        cipher.update(@ue) + cipher.final
      rescue OpenSSL::Cipher::CipherError => e
        raise EncryptedError, "failed to derive AES-256 key: #{e.message}"
      end

      # R5 uses a plain SHA-256; R6 uses the hardened hash (Algorithm 2.B).
      def hash_v5(password, salt, udata = "".b)
        return Digest::SHA256.digest(password + salt + udata) if @r == 5

        hash_r6(password, salt, udata)
      end

      def hash_r6(password, salt, udata)
        k = Digest::SHA256.digest(password + salt + udata)
        round = 0
        loop do
          k1 = (password + k + udata) * 64
          cipher = OpenSSL::Cipher.new("aes-128-cbc")
          cipher.encrypt
          cipher.padding = 0
          cipher.key = k[0, 16]
          cipher.iv = k[16, 16]
          e = cipher.update(k1) + cipher.final
          modulo = e[0, 16].bytes.sum % 3
          k =
            case modulo
            when 0 then Digest::SHA256.digest(e)
            when 1 then Digest::SHA384.digest(e)
            else Digest::SHA512.digest(e)
            end
          round += 1
          break if round >= 64 && e.bytes.last <= round - 32
        end
        k[0, 32]
      end

      # Algorithm 1: per-object key for RC4 / AESV2.
      def object_key(num, gen, aes)
        material = @key.dup
        material << [num].pack("V")[0, 3]
        material << [gen].pack("V")[0, 2]
        material << "sAlT".b if aes
        size = [@length_bytes + 5, 16].min
        Digest::MD5.digest(material)[0, size]
      end

      def rc4(key, data)
        state = (0..255).to_a
        key_bytes = key.bytes
        j = 0
        256.times do |i|
          j = (j + state[i] + key_bytes[i % key_bytes.length]) & 0xFF
          state[i], state[j] = state[j], state[i]
        end
        out = +"".b
        i = 0
        j = 0
        data.each_byte do |byte|
          i = (i + 1) & 0xFF
          j = (j + state[i]) & 0xFF
          state[i], state[j] = state[j], state[i]
          out << (byte ^ state[(state[i] + state[j]) & 0xFF]).chr
        end
        out
      end

      def aes_cbc_decrypt(key, data)
        return "".b if data.bytesize <= 16

        iv = data[0, 16]
        ciphertext = data[16..]
        algo = key.bytesize == 32 ? "aes-256-cbc" : "aes-128-cbc"
        cipher = OpenSSL::Cipher.new(algo)
        cipher.decrypt
        cipher.padding = 0
        cipher.key = key
        cipher.iv = iv
        plain = cipher.update(ciphertext) + cipher.final
        strip_pkcs7(plain)
      rescue OpenSSL::Cipher::CipherError
        "".b
      end

      def strip_pkcs7(data)
        return data if data.empty?

        pad = data.getbyte(data.bytesize - 1)
        return data if pad.nil? || pad < 1 || pad > 16 || pad > data.bytesize

        data[0...(data.bytesize - pad)]
      end

      def res(value)
        value.is_a?(Reference) ? @resolver.call(value) : value
      end

      def int(value)
        value.is_a?(Numeric) ? value.to_i : nil
      end

      def str(value)
        value.is_a?(String) ? value.b : nil
      end
    end
  end
end
