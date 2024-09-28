require "charlock_holmes"

RSpec.describe CharlockHolmes::Converter do
  describe "#convert" do
    context "converts ASCII from ISO-8859-1 to UTF-16 and back" do
      let(:input) { "test" }

      it "increases byte size on conversion to UTF-16" do
        output = CharlockHolmes::Converter.convert(input, "ISO-8859-1", "UTF-16")
        expect(output.bytesize).to be > input.bytesize
      end

      it "changes the string after conversion to UTF-16" do
        output = CharlockHolmes::Converter.convert(input, "ISO-8859-1", "UTF-16")
        expect(output).not_to eq(input)
      end

      it "returns the original string after converting back to ISO-8859-1" do
        output = CharlockHolmes::Converter.convert(input, "ISO-8859-1", "UTF-16")
        output = CharlockHolmes::Converter.convert(output, "UTF-16", "ISO-8859-1")
        expect(output).to eq(input)
      end

      it "maintains byte size after converting back to ISO-8859-1" do
        output = CharlockHolmes::Converter.convert(input, "ISO-8859-1", "UTF-16")
        output = CharlockHolmes::Converter.convert(output, "UTF-16", "ISO-8859-1")
        expect(output.bytesize).to eq(input.bytesize)
      end
    end

    context "converts UTF-8 to UTF-16 and back" do
      let(:input) { "λ, λ, λ" }

      it "increases byte size on conversion to UTF-16" do
        output = CharlockHolmes::Converter.convert(input, "UTF-8", "UTF-16")
        expect(output.bytesize).to be > input.bytesize
      end

      it "changes the string after conversion to UTF-16" do
        output = CharlockHolmes::Converter.convert(input, "UTF-8", "UTF-16")
        expect(output).not_to eq(input)
      end

      it "returns the original string after converting back to UTF-8" do
        output = CharlockHolmes::Converter.convert(input, "UTF-8", "UTF-16")
        output = CharlockHolmes::Converter.convert(output, "UTF-16", "UTF-8")
        expect(output).to eq(input)
      end

      it "maintains byte size after converting back to UTF-8" do
        output = CharlockHolmes::Converter.convert(input, "UTF-8", "UTF-16")
        output = CharlockHolmes::Converter.convert(output, "UTF-16", "UTF-8")
        expect(output.bytesize).to eq(input.bytesize)
      end
    end

    context "raises error for invalid arguments" do
      it "raises TypeError for non-string input" do
        expect { CharlockHolmes::Converter.convert(nil, "UTF-8", "UTF-16") }.to raise_error(TypeError)
      end

      it "raises TypeError for nil encoding" do
        expect { CharlockHolmes::Converter.convert("lol", nil, "UTF-16") }.to raise_error(TypeError)
      end

      it "raises TypeError for nil output encoding" do
        expect { CharlockHolmes::Converter.convert("lol", "UTF-8", nil) }.to raise_error(TypeError)
      end

      it "does not raise any exception for valid arguments" do
        expect do
          CharlockHolmes::Converter.convert("lol", "UTF-8", "UTF-16")
        end.not_to raise_error
      end
    end
  end
end
