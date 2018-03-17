require "test_helper"
require "image_processing/mini_magick"
require "stringio"

describe "ImageProcessing::MiniMagick" do
  include ImageProcessing::MiniMagick

  before do
    @portrait  = fixture_image("portrait.jpg")
    @landscape = fixture_image("landscape.jpg")
  end

  it "applies imagemagick operations" do
    actual = ImageProcessing::MiniMagick.flip.call(@portrait)
    expected = Tempfile.new(["result", ".jpg"], binmode: true).tap do |tempfile|
      MiniMagick::Tool::Convert.new do |cmd|
        cmd << @portrait.path
        cmd.flip
        cmd << tempfile.path
      end
    end

    assert_similar expected, actual
  end

  it "applies macro operations" do
    actual = ImageProcessing::MiniMagick.resize_to_limit(400, 400).call(@portrait)
    expected = Tempfile.new(["result", ".jpg"], binmode: true).tap do |tempfile|
      MiniMagick::Tool::Convert.new do |cmd|
        cmd << @portrait.path
        cmd.resize("400x400")
        cmd << tempfile.path
      end
    end

    assert_similar expected, actual
  end

  it "applies appended options" do
    actual = ImageProcessing::MiniMagick.append("-resize", "400x400").call(@portrait)
    expected = Tempfile.new(["result", ".jpg"], binmode: true).tap do |tempfile|
      MiniMagick::Tool::Convert.new do |cmd|
        cmd << @portrait.path
        cmd.resize("400x400")
        cmd << tempfile.path
      end
    end

    assert_similar expected, actual
  end

  it "applies format" do
    result = ImageProcessing::MiniMagick.convert("png").call(@portrait)
    assert_equal ".png", File.extname(result.path)
    assert_type "PNG", result
  end

  it "accepts page" do
    pdf = Tempfile.new(["file", ".pdf"])
    MiniMagick::Tool::Convert.new do |convert|
      convert.merge! [@portrait.path, @portrait.path, @portrait.path]
      convert << pdf.path
    end

    processed = ImageProcessing::MiniMagick
      .source(pdf)
      .loader(page: 0)
      .convert!("jpg")

    assert File.exist?(processed.path)
  end

  it "accepts geometry" do
    pipeline = ImageProcessing::MiniMagick.source(@portrait)
    assert_dimensions [300, 400], pipeline.loader(geometry: "400x400").call
  end

  it "fails for corrupted files" do
    corrupted = fixture_image("corrupted.jpg")
    pipeline = ImageProcessing::MiniMagick.source(corrupted)
    assert_raises(MiniMagick::Error) { pipeline.resize_to_limit!(400, 400) }
  end

  it "allows ignoring processing warnings" do
    corrupted = fixture_image("corrupted.jpg")
    pipeline = ImageProcessing::MiniMagick.source(corrupted).loader(fail: false)
    pipeline.resize_to_limit!(400, 400)
  end

  it "fails for invalid source" do
    assert_raises(ImageProcessing::Error) do
      ImageProcessing::MiniMagick.call(StringIO.new)
    end
    assert_raises(ImageProcessing::Error) do
      ImageProcessing::MiniMagick.source(StringIO.new).call
    end
  end

  describe ".valid_image?" do
    it "returns true for correct images" do
      assert ImageProcessing::MiniMagick.valid_image?(@portrait)
      assert ImageProcessing::MiniMagick.valid_image?(copy_to_tempfile(@portrait)) # no extension
    end

    it "returns false for corrupted images" do
      refute ImageProcessing::MiniMagick.valid_image?(fixture_image("corrupted.jpg"))
      refute ImageProcessing::MiniMagick.valid_image?(copy_to_tempfile(fixture_image("corrupted.jpg"))) # no extension
    end

    deprecated "still supports the legacy API" do
      assert corrupted?(@portrait)
      refute corrupted?(fixture_image("corrupted.jpg"))

      assert ImageProcessing::MiniMagick.corrupted?(@portrait)
      refute ImageProcessing::MiniMagick.corrupted?(fixture_image("corrupted.jpg"))
    end
  end

  describe "#resize_to_limit" do
    before do
      @pipeline = ImageProcessing::MiniMagick.source(@portrait)
    end

    it "srinks image to fit the specified dimensions" do
      assert_dimensions [300, 400], @pipeline.resize_to_limit!(400, 400)
    end

    it "doesn't enlarge image if it's smaller than specified dimensions" do
      assert_dimensions [600, 800], @pipeline.resize_to_limit!(1000, 1000)
    end

    it "doesn't require both dimensions" do
      assert_dimensions [300, 400], @pipeline.resize_to_limit!(300, nil)
      assert_dimensions [600, 800], @pipeline.resize_to_limit!(800, nil)

      assert_dimensions [300, 400], @pipeline.resize_to_limit!(nil, 400)
      assert_dimensions [600, 800], @pipeline.resize_to_limit!(nil, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("limit.jpg")
      assert_similar expected, @pipeline.resize_to_limit!(400, 400)
    end

    deprecated "still supports the legacy API" do
      expected = @pipeline.resize_to_limit!(400, 400)

      assert_similar expected, resize_to_limit(@portrait, 400, 400)
      assert_similar expected, resize_to_limit!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)

      assert_similar expected, ImageProcessing::MiniMagick.resize_to_limit(@portrait, 400, 400)
      assert_similar expected, ImageProcessing::MiniMagick.resize_to_limit!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)
    end
  end

  describe "#resize_to_fit" do
    before do
      @pipeline = ImageProcessing::MiniMagick.source(@portrait)
    end

    it "shrinks image to fit specified dimensions" do
      assert_dimensions [300, 400], @pipeline.resize_to_fit!(400, 400)
    end

    it "enlarges image if it's smaller than given dimensions" do
      assert_dimensions [750, 1000], @pipeline.resize_to_fit!(1000, 1000)
    end

    it "doesn't require both dimensions" do
      assert_dimensions [300, 400],  @pipeline.resize_to_fit!(300, nil)
      assert_dimensions [750, 1000], @pipeline.resize_to_fit!(750, nil)

      assert_dimensions [300, 400],  @pipeline.resize_to_fit!(nil, 400)
      assert_dimensions [750, 1000], @pipeline.resize_to_fit!(nil, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("fit.jpg")
      assert_similar expected, @pipeline.resize_to_fit!(400, 400)
    end

    deprecated "still supports the legacy API" do
      expected = @pipeline.resize_to_fit!(400, 400)

      assert_similar expected, resize_to_fit(@portrait, 400, 400)
      assert_similar expected, resize_to_fit!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)

      assert_similar expected, ImageProcessing::MiniMagick.resize_to_fit(@portrait, 400, 400)
      assert_similar expected, ImageProcessing::MiniMagick.resize_to_fit!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)
    end
  end

  describe "#resize_to_fill" do
    before do
      @pipeline = ImageProcessing::MiniMagick.source(@portrait)
    end

    it "resizes and crops the image to fill out the given dimensions" do
      assert_dimensions [400, 400], @pipeline.resize_to_fill!(400, 400)
    end

    it "enlarges image and crops it if it's smaller than given dimensions" do
      assert_dimensions [1000, 1000], @pipeline.resize_to_fill!(1000, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("fill.jpg")
      assert_similar expected, @pipeline.resize_to_fill!(400, 400)
    end

    it "accepts gravity" do
      centre    = @pipeline.resize_to_fill!(400, 400)
      northwest = @pipeline.resize_to_fill!(400, 400, gravity: "NorthWest")
      refute_similar centre, northwest
    end

    deprecated "still supports the legacy API" do
      expected = @pipeline.resize_to_fill!(400, 400)

      assert_similar expected, resize_to_fill(@portrait, 400, 400)
      assert_similar expected, resize_to_fill!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)

      assert_similar expected, ImageProcessing::MiniMagick.resize_to_fill(@portrait, 400, 400)
      assert_similar expected, ImageProcessing::MiniMagick.resize_to_fill!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)
    end
  end

  describe "#resize_and_pad" do
    before do
      @pipeline = ImageProcessing::MiniMagick.source(@portrait)
    end

    it "resizes and fills out the remaining space to fill out the given dimensions" do
      assert_dimensions [400, 400], @pipeline.resize_and_pad!(400, 400)
    end

    it "enlarges image and fills out the remaining space to fill out the given dimensions" do
      assert_dimensions [1000, 1000], @pipeline.resize_and_pad!(1000, 1000)
    end

    it "produces correct image" do
      expected = fixture_image("pad.jpg")
      assert_similar expected, @pipeline.resize_and_pad!(400, 400, background: "red")
    end

    it "produces correct image when enlarging" do
      @pipeline = ImageProcessing::MiniMagick.source(@landscape)
      expected = fixture_image("pad-large.jpg")
      assert_similar expected, @pipeline.resize_and_pad!(1000, 1000, background: "green")
    end

    it "accepts gravity" do
      centre    = @pipeline.resize_and_pad!(400, 400)
      northwest = @pipeline.resize_and_pad!(400, 400, gravity: "NorthWest")
      refute_similar centre, northwest
    end

    it "accepts transparent color" do
      transparent = @pipeline.resize_and_pad!(400, 400, background: "transparent")
      default     = @pipeline.resize_and_pad!(400, 400)
      assert_similar transparent, default
    end

    deprecated "still supports the legacy API" do
      expected = @pipeline.resize_and_pad!(400, 400)

      assert_similar expected, resize_and_pad(@portrait, 400, 400)
      assert_similar expected, resize_and_pad!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)

      assert_similar expected, ImageProcessing::MiniMagick.resize_and_pad(@portrait, 400, 400)
      assert_similar expected, ImageProcessing::MiniMagick.resize_and_pad!(copy_to_tempfile(@portrait, ".jpg"), 400, 400)
    end
  end
end
