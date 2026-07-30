# frozen_string_literal: true

require "digest"
require "openssl"
require_relative "pdf_builder"

# Builds encrypted PDFs for tests using an independent implementation of the
# PDF standard security handler's *generation* algorithms (Algorithms 2-6).
# The library implements the *reading* side, so a successful round-trip
# cross-checks the two implementations rather than testing code against itself.
#
# Both the user and owner passwords are empty, matching the common
# "permissions only" encryption that RUDF opens automatically.
module EncryptedPDFBuilder
  module_function

  PAD = RUDF::PDF::Crypto::PAD

  # Build a single-page encrypted PDF. +method+ is :rc4 (V2/R3) or :aes
  # (V4/R4, AES-128). Returns the raw bytes.
  def single_page(text: "Secret text", title: "Classified", method: :rc4)
    id = "0123456789ABCDEF".b
    p = -44 # a typical permissions value (allow print, etc.)
    key_bytes = method == :aes ? 16 : 16
    r = 4
    v = method == :aes ? 4 : 2

    o = compute_o(key_bytes, r)
    key = compute_key(o, p, id, key_bytes, r)
    u = compute_u(key, id, r)

    content = "BT /F1 24 Tf 72 700 Td (#{PDFBuilder.escape(text)}) Tj ET"

    # Object bodies. Strings/streams inside 4 (content) and 7 (info) are
    # encrypted per-object; structural dicts have no encryptable data.
    plain = {
      1 => "<< /Type /Catalog /Pages 2 0 R >>",
      2 => "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      3 => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] " \
           "/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
      5 => "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    }

    enc_content = encrypt_data(content.b, 4, 0, key, method)
    enc_title = encrypt_data(title.b, 7, 0, key, method)

    objects = {}
    plain.each { |n, body| objects[n] = body }
    objects[4] = "<< /Length #{enc_content.bytesize} >>\nstream\n#{enc_content}\nendstream"
    objects[7] = "<< /Title (#{escape_bin(enc_title)}) /Producer (RUDF) >>"
    objects[6] = encrypt_dict(v, r, key_bytes, o, u, p, method)

    assemble(objects, id)
  end

  # ---- assembly --------------------------------------------------------------

  def assemble(objects, id)
    out = +"%PDF-1.6\n%\xE2\xE3\xCF\xD3\n".b
    offsets = {}
    objects.keys.sort.each do |num|
      offsets[num] = out.bytesize
      out << "#{num} 0 obj\n#{objects[num]}\nendobj\n".b
    end
    xref = out.bytesize
    max = objects.keys.max
    out << "xref\n0 #{max + 1}\n0000000000 65535 f \n".b
    (1..max).each do |num|
      out << (offsets[num] ? format("%010d 00000 n \n", offsets[num]) : "0000000000 00000 f \n").b
    end
    hexid = id.unpack1("H*")
    out << "trailer\n<< /Size #{max + 1} /Root 1 0 R /Info 7 0 R " \
           "/Encrypt 6 0 R /ID [<#{hexid}> <#{hexid}>] >>\n".b
    out << "startxref\n#{xref}\n%%EOF\n".b
    out.b
  end

  def encrypt_dict(v, r, key_bytes, o, u, p, method)
    base = +"<< /Filter /Standard /V #{v} /R #{r} /Length #{key_bytes * 8} " \
           "/P #{p} /O (#{escape_bin(o)}) /U (#{escape_bin(u)})"
    if method == :aes
      base << " /CF << /StdCF << /CFM /AESV2 /Length #{key_bytes} >> >> " \
              "/StmF /StdCF /StrF /StdCF"
    end
    base << " >>"
    base
  end

  # ---- standard security handler generation ---------------------------------

  # Algorithm 3: owner key with empty owner+user passwords.
  def compute_o(key_bytes, r)
    rc4_key = Digest::MD5.digest(PAD)
    rc4_key = 50.times.inject(rc4_key) { |k, _| Digest::MD5.digest(k[0, key_bytes]) } if r >= 3
    rc4_key = rc4_key[0, key_bytes]
    data = PAD.dup
    if r >= 3
      20.times do |i|
        k = rc4_key.bytes.map { |b| b ^ i }.pack("C*")
        data = rc4(k, data)
      end
    else
      data = rc4(rc4_key, data)
    end
    data
  end

  # Algorithm 2: the file encryption key (empty user password).
  def compute_key(o, p, id, key_bytes, r)
    md5 = Digest::MD5.new
    md5 << PAD
    md5 << o[0, 32]
    md5 << [p].pack("l<")
    md5 << id
    key = md5.digest
    key = 50.times.inject(key) { |k, _| Digest::MD5.digest(k[0, key_bytes]) } if r >= 3
    key[0, key_bytes]
  end

  # Algorithm 5 (R3+): the user password verifier.
  def compute_u(key, id, r)
    if r >= 3
      base = Digest::MD5.digest(PAD + id)
      enc = base
      20.times do |i|
        k = key.bytes.map { |b| b ^ i }.pack("C*")
        enc = rc4(k, enc)
      end
      enc + ("\x00" * 16).b
    else
      rc4(key, PAD)
    end
  end

  # ---- per-object encryption -------------------------------------------------

  def encrypt_data(data, num, gen, key, method)
    aes = method == :aes
    material = key.dup
    material << [num].pack("V")[0, 3]
    material << [gen].pack("V")[0, 2]
    material << "sAlT".b if aes
    obj_key = Digest::MD5.digest(material)[0, [key.bytesize + 5, 16].min]

    if aes
      iv = OpenSSL::Random.random_bytes(16)
      cipher = OpenSSL::Cipher.new("aes-128-cbc")
      cipher.encrypt
      cipher.key = obj_key
      cipher.iv = iv
      iv + cipher.update(data) + cipher.final
    else
      rc4(obj_key, data)
    end
  end

  # Pure-Ruby RC4 (OpenSSL 3+ no longer ships RC4 in the default provider).
  def rc4(key, data)
    state = (0..255).to_a
    kb = key.bytes
    j = 0
    256.times do |i|
      j = (j + state[i] + kb[i % kb.length]) & 0xFF
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

  # Escape a binary string for a PDF literal +( )+ string.
  def escape_bin(bytes)
    out = +"".b
    bytes.each_byte do |b|
      case b
      when 0x5C then out << "\\\\"
      when 0x28 then out << "\\("
      when 0x29 then out << "\\)"
      when 0x0A then out << "\\n"
      when 0x0D then out << "\\r"
      else out << b.chr
      end
    end
    out
  end
end
