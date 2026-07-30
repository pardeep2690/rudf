# frozen_string_literal: true

module RUDF
  # Base class for all errors raised by RUDF.
  class Error < StandardError; end

  # Raised when a file cannot be opened or does not exist.
  class FileNotFoundError < Error; end

  # Raised when the underlying data is not a valid / supported document.
  class FileDataError < Error; end

  # Raised when a requested page is out of range.
  class PageNotFoundError < Error; end

  # Raised for malformed PDF syntax encountered while parsing.
  class ParseError < Error; end

  # Raised when an operation is attempted on a closed document.
  class DocumentClosedError < Error; end

  # Raised when a document is encrypted and cannot be read without a password.
  class EncryptedError < Error; end
end
