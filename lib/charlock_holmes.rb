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
    if FFI::Platform::IS_MAC
      lib_files = dir.glob("libicui18n.*.dylib")
      raise "No CharlockHolmes library found in the specified directory" if lib_files.empty?

      # Extract the version number from the first matching file
      highest_version = lib_files.first.basename.to_s.match(/libicui18n\.(\d+)\./)[1].to_i
    elsif FFI::Platform::IS_LINUX

      # Check for versioned library files
      versioned_libs = dir.glob("libicui18n.so.*")

      raise "No CharlockHolmes library found in the specified directory" if versioned_libs.empty?

      # Find the highest version number
      highest_version = versioned_libs.map do |lib|
        lib.basename.to_s.to_s.match(/\w+\.(\d+)/).captures[0]
      end.max

    else
      raise "un supported platform"
    end
    highest_version
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
      return {type: :binary, confidence: 100, encoding: "BINARY", ruby_encoding: "ASCII-8BIT"} if is_binary?(text_to_detect)

      status = FFI::MemoryPointer.new(:int)
      charset_detector = CharlockHolmes.ucsdet_open(status)

      CharlockHolmes.ucsdet_setText(charset_detector, text_to_detect, text_to_detect.length, status)
      detected_charset = CharlockHolmes.ucsdet_detect(charset_detector, status)
      confidence = CharlockHolmes.ucsdet_getConfidence(detected_charset, status)
      name = CharlockHolmes.ucsdet_getName(detected_charset, status)
      language = CharlockHolmes.ucsdet_getLanguage(detected_charset, status)
      CharlockHolmes.ucsdet_close(charset_detector)
      ruby_encoding = begin
        Encoding.find(name).name
      rescue
        "binary"
      end
      {
        encoding: name,
        confidence: confidence,
        type: :text,
        language: language,
        ruby_encoding: ruby_encoding
      }
    end

    def type
      if is_binary?
        :binary
      else
        :text
      end
    end

    def is_binary?(text_to_detect)
      buf = text_to_detect # .force_encoding("ASCII-8BIT") # Ensures the string is treated as binary
      buf_len = buf.length
      scan_len = [buf_len, DEFAULT_BINARY_SCAN_LEN].min

      if buf_len > 10
        # application/postscript
        return false if buf.start_with?("%!PS-Adobe-")
      end

      if buf_len > 7
        # image/png
        return true if buf.start_with?("\x89PNG\x0D\x0A\x1A\x0A")
      end

      if buf_len > 5
        # image/gif
        return true if buf.start_with?("GIF87a")

        # image/gif
        return true if buf.start_with?("GIF89a")
      end

      if buf_len > 4
        # application/pdf
        return true if buf.start_with?("%PDF-")
      end

      if buf_len > 3
        # UTF-32BE
        return false if buf.start_with?("\0\0\xfe\xff")

        # UTF-32LE
        return false if buf.start_with?("\xff\xfe\0\0")
      end

      if buf_len > 2
        # image/jpeg
        return true if buf.start_with?("\xFF\xD8\xFF")
      end

      if buf_len > 1
        # UTF-16BE
        return false if buf.start_with?("\xfe\xff")

        # UTF-16LE
        return false if buf.start_with?("\xff\xfe")
      end

      # Check for NULL bytes within the scan range, likely indicating binary content
      buf_len = [buf_len, scan_len].min
      buf[0...buf_len].include?("\0")
    end

    def supported_encodings
      []
    end

    def self.supported_encodings
      new.supported_encodings
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
        ruby_encoding = begin
          Encoding.find(name).name
        rescue
          nil
        end
        results << {encoding: name, confidence: confidence, type: :text, language: language,
                     ruby_encoding: ruby_encoding}
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

      target_encoding = "UTF-16BE" if target_encoding == "UTF-16" # FIXME it seems that ruby 3.2+ defaults to Big endian

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
