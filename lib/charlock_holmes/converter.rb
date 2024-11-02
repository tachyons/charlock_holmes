module CharlockHolmes
  class Converter
    def self.convert(text, source_encoding, target_encoding)
      new.convert(text, source_encoding, target_encoding)
    end

    def convert(text, source_encoding, target_encoding)
      raise TypeError if text.nil? || source_encoding.nil? || target_encoding.nil?
      text = text.dup.force_encoding(Encoding::BINARY) # Ensures the string is treated as binary

      target_encoding = "UTF-16BE" if target_encoding == "UTF-16" # FIXME it seems that ruby 3.2+ defaults to Big endian

      status = FFI::MemoryPointer.new(:int)
      source_encoding = "ASCII" if source_encoding == "BINARY"
      source_conv = CharlockHolmes.ucnv_open(source_encoding, status)
      target_conv = CharlockHolmes.ucnv_open(target_encoding, status)

      raise "Failed to open source converter #{source_encoding}" if source_conv.null?
      raise "Failed to open target converter #{target_encoding}" if target_conv.null?

      source_length = text.bytesize
      target_length = source_length * 4 # Estimate target size
      target_buffer = FFI::MemoryPointer.new(:char, target_length)

      text_pointer = FFI::MemoryPointer.from_string(text)
      # Convert the text
      converted_length = CharlockHolmes.ucnv_convert(
        target_encoding,
        source_encoding,
        target_buffer,
        target_length,
        text_pointer,
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
