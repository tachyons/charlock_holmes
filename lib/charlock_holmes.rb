# frozen_string_literal: true

require "ffi"
require "rbconfig"
require "pathname"

require_relative "charlock_holmes/version"
require_relative "charlock_holmes/converter"
require_relative "charlock_holmes/encoding_detector"

module CharlockHolmes
  extend FFI::Library

  class Error < StandardError; end

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

  abi_version = get_icu_version

  # Load both libicui18n and libicuuc

  icu_lib_path_i18n = FFI::LibraryPath.new("icui18n", abi_number: abi_version, root: icu_dir)

  icu_lib_path_uc = FFI::LibraryPath.new("icuuc", abi_number: abi_version, root: icu_dir)

  ffi_lib(icu_lib_path_i18n, icu_lib_path_uc)

  # Define necessary types and attach functions with dynamic version postfixes
  typedef :pointer, :UCharsetDetector
  typedef :pointer, :UCharsetMatch
  typedef :pointer, :UCharsetMatchArray
  typedef :pointer, :UErrorCode
  typedef :pointer, :UConverter
  typedef :pointer, :StringWithNullByte

  attach_function :ucsdet_open, :"ucsdet_open_#{abi_version}", [:pointer], :UCharsetDetector
  attach_function :ucsdet_close, :"ucsdet_close_#{abi_version}", [:UCharsetDetector], :void
  attach_function :ucsdet_setText, :"ucsdet_setText_#{abi_version}",
    %i[UCharsetDetector StringWithNullByte int pointer], :int
  attach_function :ucsdet_detect, :"ucsdet_detect_#{abi_version}", %i[UCharsetDetector pointer],
    :UCharsetMatch
  attach_function :ucsdet_getConfidence, :"ucsdet_getConfidence_#{abi_version}", %i[UCharsetMatch pointer],
    :int
  attach_function :ucsdet_getName, :"ucsdet_getName_#{abi_version}", %i[UCharsetMatch pointer], :string
  attach_function :ucsdet_getLanguage, :"ucsdet_getLanguage_#{abi_version}", %i[UCharsetMatch pointer],
    :string
  attach_function :ucsdet_detectAll, :"ucsdet_detectAll_#{abi_version}", %i[UCharsetDetector pointer UErrorCode],
    :UCharsetMatchArray

  attach_function :ucsdet_getAllDetectableCharsets, :"ucsdet_getAllDetectableCharsets_#{abi_version}", [:pointer, :pointer], :pointer
  attach_function :uenum_count, :"uenum_count_#{abi_version}", [:pointer, :pointer], :int32
  attach_function :uenum_next, :"uenum_next_#{abi_version}", [:pointer, :pointer, :pointer], :string

  attach_function :ucnv_convert, :"ucnv_convert_#{abi_version}", [
    :string,  # toConverterName
    :string,  # fromConverterName
    :pointer, # target
    :int32,   # targetCapacity
    :StringWithNullByte,  # source
    :int32,   # sourceLength
    :pointer  # pErrorCode
  ], :int32

  attach_function :ucnv_open, :"ucnv_open_#{abi_version}", %i[string pointer], :pointer
  attach_function :ucnv_close, :"ucnv_close_#{abi_version}", [:pointer], :void
  attach_function :ucnv_getMaxCharSize, :"ucnv_getMaxCharSize_#{abi_version}", [:pointer], :int
end
