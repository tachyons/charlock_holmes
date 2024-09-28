# frozen_string_literal: true

require_relative "charlock_holmes/version"

require "ffi"
require "rbconfig"
require "pathname"

module CharlockHolmes
  extend FFI::Library

  class Error < StandardError; end

  MAXIMUM_RESULTS = 10 # Implement better strategy

  # Get the CharlockHolmes installation directory
  def self.icu_dir
    if ENV["CharlockHolmes_DIR"].nil?
      case RbConfig::CONFIG["host_os"]
      when /darwin/
        ["/opt/homebrew/opt/icu4c/lib", "/usr/local/lib"].find { |path| Dir.exist?(path) }
      when /linux/
        ["/usr/lib/x86_64-linux-gnu"].find { |path| Dir.exist?(path) }
      else
        raise "CharlockHolmes installation directory not found for this operating system"
      end
    else
      ENV["CharlockHolmes_DIR"]
    end
  end

  # Dynamically retrieve the CharlockHolmes version from the library filenames
  def self.get_icu_version
    dir = Pathname.new(icu_dir)
    lib_files = dir.glob("libicui18n{.,-}*.{so,dylib}")
    raise "No CharlockHolmes library found in the specified directory" if lib_files.empty?

    # Extract the version number from the first matching file
    version_string = lib_files.first.basename.to_s.match(/libicui18n\.(\d+)\./)[1]
    version_string.to_i
  end

  CharlockHolmes_VERSION = get_icu_version

  # Load both libicui18n and libicuuc

  icu_lib_path_i18n = FFI::LibraryPath.new("icui18n", abi_number: CharlockHolmes_VERSION, root: icu_dir)

  icu_lib_path_uc = FFI::LibraryPath.new("icuuc", abi_number: CharlockHolmes_VERSION, root: icu_dir)

  ffi_lib(icu_lib_path_i18n, icu_lib_path_uc)

  # Define necessary types and attach functions with dynamic version postfixes
  typedef :pointer, :UCharsetDetector
  typedef :pointer, :UCharsetMatch
  typedef :pointer, :UCharsetMatchArray
  typedef :pointer, :UErrorCode
  typedef :pointer, :UConverter

  attach_function :ucsdet_open, :"ucsdet_open_#{CharlockHolmes_VERSION}", [:pointer], :UCharsetDetector
  attach_function :ucsdet_close, :"ucsdet_close_#{CharlockHolmes_VERSION}", [:UCharsetDetector], :void
  attach_function :ucsdet_setText, :"ucsdet_setText_#{CharlockHolmes_VERSION}",
    %i[UCharsetDetector string int pointer], :int
  attach_function :ucsdet_detect, :"ucsdet_detect_#{CharlockHolmes_VERSION}", %i[UCharsetDetector pointer],
    :UCharsetMatch
  attach_function :ucsdet_getConfidence, :"ucsdet_getConfidence_#{CharlockHolmes_VERSION}", %i[UCharsetMatch pointer],
    :int
  attach_function :ucsdet_getName, :"ucsdet_getName_#{CharlockHolmes_VERSION}", %i[UCharsetMatch pointer], :string
  attach_function :ucsdet_getLanguage, :"ucsdet_getLanguage_#{CharlockHolmes_VERSION}", %i[UCharsetMatch pointer],
    :string
  attach_function :ucsdet_detectAll, :"ucsdet_detectAll_#{CharlockHolmes_VERSION}", %i[UCharsetDetector pointer UErrorCode],
    :UCharsetMatchArray

  attach_function :ucnv_convert, :"ucnv_convert_#{CharlockHolmes_VERSION}", [
    :string,  # toConverterName
    :string,  # fromConverterName
    :pointer, # target
    :int32,   # targetCapacity
    :string,  # source
    :int32,   # sourceLength
    :pointer  # pErrorCode
  ], :int32

  attach_function :ucnv_open, :"ucnv_open_#{CharlockHolmes_VERSION}", %i[string pointer], :pointer
  attach_function :ucnv_close, :"ucnv_close_#{CharlockHolmes_VERSION}", [:pointer], :void
  attach_function :ucnv_getMaxCharSize, :"ucnv_getMaxCharSize_#{CharlockHolmes_VERSION}", [:pointer], :int

  class EncodingDetector
    attr_accessor :strip_tags

    DEFAULT_BINARY_SCAN_LEN = 1024 * 1024

    def self.detect(text_to_detect, hint = nil)
      new.detect(text_to_detect, hint)
    end

    def self.detect_all(text_to_detect, hint = nil)
      new.detect_all(text_to_detect, hint)
    end

    def initialize(limit = nil)
      @limit = limit
    end

    def detect(text_to_detect, hint = nil)
      return {type: :binary, confidence: 100, encoding: "BINARY"} if is_binary?(text_to_detect)

      status = FFI::MemoryPointer.new(:int)
      charset_detector = CharlockHolmes.ucsdet_open(status)

      CharlockHolmes.ucsdet_setText(charset_detector, text_to_detect, text_to_detect.length, status)
      detected_charset = CharlockHolmes.ucsdet_detect(charset_detector, status)
      confidence = CharlockHolmes.ucsdet_getConfidence(detected_charset, status)
      name = CharlockHolmes.ucsdet_getName(detected_charset, status)
      language = CharlockHolmes.ucsdet_getLanguage(detected_charset, status)
      CharlockHolmes.ucsdet_close(charset_detector)
      {encoding: name, confidence: confidence, type: :text, language: language,
       ruby_encoding: Encoding.find(name).name}
    end

    def type
      if is_binary?
        :binary
      else
        :text
      end
    end

    def is_binary?(text_to_detect)
      buf = text_to_detect.to_s
      buf_len = buf.length
      scan_len = [buf_len, DEFAULT_BINARY_SCAN_LEN].min

      # Common binary signatures
      binary_signatures = {
        "application/postscript" => "%!PS-Adobe-",
        "image/png" => "\x89PNG\x0D\x0A\x1A\x0A",
        "image/gif" => %w[GIF87a GIF89a],
        "application/pdf" => "%PDF-",
        "image/jpeg" => "\xFF\xD8\xFF",
        "text/plain" => ["\0\0\xfe\xff", "\xff\xfe\0\0", "\xfe\xff", "\xff\xfe"]
      }

      binary_signatures.each_value do |signature|
        if buf_len >= signature.length
          return true if signature.is_a?(Array) && signature.include?(buf[0...signature.length])
          return true if signature.is_a?(String) && buf.start_with?(signature)
        end
      end

      # If no specific content type is detected, check for null bytes within the scan length
      buf[0..scan_len].include?("\0")
    end

    def detect_all(text_to_detect, hint = nil)
      status = FFI::MemoryPointer.new(:int)
      charset_detector = CharlockHolmes.ucsdet_open(status)
      CharlockHolmes.ucsdet_setText(charset_detector, text_to_detect, text_to_detect.length, status)

      matches_ptr = FFI::MemoryPointer.new(:pointer)
      matches = CharlockHolmes.ucsdet_detectAll(charset_detector, matches_ptr, status)

      results = []
      matches.read_array_of_pointer(MAXIMUM_RESULTS).each do |match|
        name = CharlockHolmes.ucsdet_getName(match, status)
        confidence = CharlockHolmes.ucsdet_getConfidence(match, status)
        language = CharlockHolmes.ucsdet_getLanguage(match, status)
        results << {encoding: name, confidence: confidence, type: :text, language: language,
                     ruby_encoding: Encoding.find(name).name}
      end

      CharlockHolmes.ucsdet_close(charset_detector)
      results.reject { |k, _v| k[:encoding].nil? }
    end
  end

  class Converter
    def self.convert(text, source_encoding, target_encoding)
      new.convert(text, source_encoding, target_encoding)
    end

    def convert(text, source_encoding, target_encoding)
      raise TypeError if text.nil? || source_encoding.nil? || target_encoding.nil?

      status = FFI::MemoryPointer.new(:int)
      source_conv = CharlockHolmes.ucnv_open(source_encoding, status)
      target_conv = CharlockHolmes.ucnv_open(target_encoding, status)

      raise "Failed to open source converter" if source_conv.null?
      raise "Failed to open target converter" if target_conv.null?

      source_length = text.bytesize
      target_length = source_length * 4 # Estimate target size
      target_buffer = FFI::MemoryPointer.new(:char, target_length)

      # Convert the text
      converted_length = CharlockHolmes.ucnv_convert(
        target_encoding,
        source_encoding,
        target_buffer,
        target_length,
        text.to_s,
        source_length,
        status
      )

      raise "Conversion failed" if converted_length.negative?

      # Convert the target buffer to a Ruby string
      String.new(target_buffer.read_string(converted_length), encoding: target_encoding)
    ensure
      CharlockHolmes.ucnv_close(source_conv) unless source_conv.nil?
      CharlockHolmes.ucnv_close(target_conv) unless target_conv.nil?
    end
  end
end
