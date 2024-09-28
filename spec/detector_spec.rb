require "spec_helper"

RSpec.describe CharlockHolmes::EncodingDetector do
  let(:detector) { described_class.new }

  def fixture(file)
    File.open(File.expand_path("../spec/fixtures/#{file}", __dir__))
  end

  describe ".detect" do
    it "responds to class level detect method" do
      expect(described_class).to respond_to(:detect)
    end

    it "detects the encoding of a given string" do
      detected = described_class.detect("test")
      expect(detected[:encoding]).to eq("ISO-8859-1")
    end

    it "accepts an encoding hint" do
      detected = described_class.detect("test", "UTF-8")
      expect(detected[:encoding]).to eq("ISO-8859-1")
    end
  end

  describe ".detect_all" do
    it "responds to class level detect_all method" do
      expect(described_class).to respond_to(:detect_all)
    end

    it "detects all possible encodings of a given string" do
      detected_list = described_class.detect_all("test")
      expect(detected_list).to be_an(Array)

      encoding_list = detected_list.map { |d| d[:encoding] }.sort
      expected_list = ["ISO-8859-1", "ISO-8859-2", "UTF-8"]
      expect(encoding_list & expected_list).to eq(expected_list)
    end

    it "accepts an encoding hint" do
      detected_list = described_class.detect_all("test", "UTF-8")
      expect(detected_list).to be_an(Array)

      encoding_list = detected_list.map { |d| d[:encoding] }.sort
      expected_list = ["ISO-8859-1", "ISO-8859-2", "UTF-8"]
      expect(encoding_list & expected_list).to eq(expected_list)
    end
  end

  describe "#detect" do
    it "responds to detect method" do
      expect(detector).to respond_to(:detect)
    end

    it "detects the encoding of a given string" do
      detected = detector.detect("test")
      expect(detected[:encoding]).to eq("ISO-8859-1")
    end

    it "accepts an encoding hint" do
      detected = detector.detect("test", "UTF-8")
      expect(detected[:encoding]).to eq("ISO-8859-1")
    end
  end

  describe "#detect_all" do
    it "responds to detect_all method" do
      expect(detector).to respond_to(:detect_all)
    end

    it "detects all possible encodings of a given string" do
      detected_list = detector.detect_all("test")
      expect(detected_list).to be_an(Array)

      encoding_list = detected_list.map { |d| d[:encoding] }.sort
      expected_list = ["ISO-8859-1", "ISO-8859-2", "UTF-8"]
      expect(encoding_list & expected_list).to eq(expected_list)
    end

    it "accepts an encoding hint" do
      detected_list = detector.detect_all("test", "UTF-8")
      expect(detected_list).to be_an(Array)

      encoding_list = detected_list.map { |d| d[:encoding] }.sort
      expected_list = ["ISO-8859-1", "ISO-8859-2", "UTF-8"]
      expect(encoding_list & expected_list).to eq(expected_list)
    end
  end

  describe "#strip_tags" do
    it "enables and disables strip_tags" do
      detector.strip_tags = true
      expect(detector.strip_tags).to be true

      detection = detector.detect("<div ascii_attribute='some more ascii'>λ, λ, λ</div>")
      expect(detection[:encoding]).to eq("UTF-8")

      detector.strip_tags = false
      expect(detector.strip_tags).to be false

      detection = detector.detect("<div ascii_attribute='some more ascii'>λ, λ, λ</div>")
      expect(detection[:encoding]).to eq("UTF-8")
    end
  end

  xdescribe ".supported_encodings" do
    it "provides a list of supported encodings" do
      expect(described_class).to respond_to(:supported_encodings)
      supported_encodings = described_class.supported_encodings

      expect(supported_encodings).to be_an(Array)
      expect(supported_encodings).to include("UTF-8", "windows-1250", "windows-1252", "windows-1253", "windows-1254", "windows-1255")
    end
  end

  describe "#ruby_encoding" do
    it "returns a ruby-compatible encoding name" do
      detected = detector.detect("test")
      expect(detected[:encoding]).to eq("ISO-8859-1")
      expect(detected[:ruby_encoding]).to eq("ISO-8859-1")

      not_compat_txt = fixture("ISO-2022-KR.txt").read
      detected = detector.detect(not_compat_txt)
      expect(detected[:encoding]).to eq("ISO-2022-KR")
      expect(detected[:ruby_encoding]).to eq("binary")

      detected = detector.detect("\0\0")
      expect(detected[:encoding]).to eq("BINARY")
      expect(detected[:ruby_encoding]).to eq("ASCII-8BIT")
    end
  end

  describe "#is_binary?" do
    it "correctly identifies binary files" do
      png = fixture("octocat.png").read
      expect(detector.is_binary?(png)).to be true

      utf16 = fixture("AnsiGraph.psm1").read
      expect(detector.is_binary?(utf16)).to be false

      utf8 = fixture("core.rkt").read
      expect(detector.is_binary?(utf8)).to be false
    end
  end

  describe "detection works as expected" do
    maping = [
      ["repl2.cljs", "ISO-8859-1", :text],
      ["cl-messagepack.lisp", "ISO-8859-1", :text],
      ["sierpinski.ps", "ISO-8859-1", :text],
      ["core.rkt", "UTF-8", :text],
      ["TwigExtensionsDate.es.yml", "UTF-8", :text],
      ["laholator.py", "UTF-8", :text],
      ["vimrc", "UTF-8", :text],
      # ["AnsiGraph.psm1", "UTF-16LE", :text],
      # ["utf16be.html", "UTF-16BE", :text],
      # ["utf32le.html", "UTF-32LE", :text],
      # ["utf32be.html", "UTF-32BE", :text],
      ["hello_world", "BINARY", :binary],
      ["octocat.png", "BINARY", :binary],
      ["octocat.jpg", "BINARY", :binary],
      ["octocat.psd", "BINARY", :binary],
      ["octocat.gif", "BINARY", :binary],
      ["octocat.ai", "BINARY", :binary],
      ["foo.pdf", "BINARY", :binary]
    ]

    maping.each do |file, encoding, type|
      it "detects the encoding for #{file}" do
        content = fixture(file).read
        guessed = detector.detect(content)

        if encoding.nil?
          expect(guessed[:encoding]).to be_nil
        else
          expect(guessed[:encoding]).to eq(encoding)
        end

        expect(guessed[:type]).to eq(type)

        if content.respond_to?(:force_encoding) && guessed[:type] == :text
          content.force_encoding(guessed[:encoding])
          expect(content.valid_encoding?).to be true
        end
      end
    end
  end
end
