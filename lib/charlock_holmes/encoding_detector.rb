require_relative "../charlock_holmes"
module CharlockHolmes
  class EncodingDetector
    attr_accessor :strip_tags

    DEFAULT_BINARY_SCAN_LEN = 1024 * 1024
    MAXIMUM_RESULTS = 10

    # Length for which to scan content for NULL bytes
    attr_accessor :binary_scan_length

    def self.detect(text_to_detect, hint = nil)
      new.detect(text_to_detect, hint)
    end

    def self.detect_all(text_to_detect, hint = nil)
      new.detect_all(text_to_detect, hint)
    end

    @encoding_table = {}

    def self.encoding_table
      @encoding_table
    end

    def self.build_encoding_table
      supported_encodings.each do |name|
        @encoding_table[name] = begin
          ::Encoding.find(name).name
        rescue ArgumentError
          BINARY
        end
      end
    end

    def self.supported_encodings
      return @encoding_list if @encoding_list

      status = FFI::MemoryPointer.new(:int) # UErrorCode pointer
      status.write_int(0)  # U_ZERO_ERROR
      csd = CharlockHolmes.ucsdet_open(status)
      encoding_list = CharlockHolmes.ucsdet_getAllDetectableCharsets(csd, status)
      enc_count = CharlockHolmes.uenum_count(encoding_list, status)

      # Initialize encoding list
      @encoding_list = []

      # Add some predefined encodings
      @encoding_list << "windows-1250"
      @encoding_list << "windows-1252"
      @encoding_list << "windows-1253"
      @encoding_list << "windows-1254"
      @encoding_list << "windows-1255"

      # Iterate over detectable encodings and add them to the list
      enc_name_len = FFI::MemoryPointer.new(:int)
      enc_count.times do
        enc_name = CharlockHolmes.uenum_next(encoding_list, enc_name_len, status)
        @encoding_list << enc_name unless enc_name.nil?
      end

      CharlockHolmes.ucsdet_close(csd)
      @encoding_list
    end

    BINARY = "binary"

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
end
