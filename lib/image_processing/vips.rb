require "image_processing/version"
require "vips"
require "tempfile"

module ImageProcessing
  module Vips
    module_function

    def convert!(image, format, page = nil, &block)
      with_ruby_vips(image) do |img|
        tmp_name = tmp_name(image.path, "_tmp.#{format}")
        img.write_to_file(tmp_name)
        tmp_name
      end
    end

    def auto_orient!(image)
      with_ruby_vips(image) do |img|
        img.autorot
        tmp_name = tmp_name(image.path)
        img.write_to_file(tmp_name)
        tmp_name
      end
    end

    def resize_to_limit!(image, width, height)
      with_ruby_vips(image) do |img|
        img = resize_image(img, width, height) if width < img.width || height < img.height
        tmp_name = tmp_name(image.path)
        img.write_to_file(tmp_name)
        tmp_name
      end
    end

    def resize_to_fit!(image, width, height)
      with_ruby_vips(image) do |img|
        img = resize_image(img, width, height)
        tmp_name = tmp_name(image.path)
        img.write_to_file(tmp_name)
        tmp_name
      end
    end
    # Convert an image into a MiniMagick::Image for the duration of the block,
    # and at the end return a File object.
    def with_ruby_vips(image)
      image = ::Vips::Image.new_from_file image.path
      file_path = yield image
      File.new(file_path)
    end

    # Creates a copy of the file and stores it into a Tempfile. Works for any
    # IO object that responds to `#read(length = nil, outbuf = nil)`.
    def _copy_to_tempfile(file)
      extension = File.extname(file.path) if file.respond_to?(:path)
      tempfile = Tempfile.new(["vips", extension.to_s], binmode: true)
      IO.copy_stream(file, tempfile.path)
      file.rewind
      tempfile
    end

    def tmp_name(path, ext='_tmp\1')
      ext_regex = /(\.[[:alnum:]]+)$/
      path.sub(ext_regex, ext)
    end

    def resize_image(image, width, height, min_or_max = :min)
      ratio = get_ratio image, width, height, min_or_max
      return image if ratio == 1
      image = if ratio > 1
                image.resize(ratio, kernel: :nearest)
              else
                image.resize(ratio, kernel: :cubic)
              end
      image
    end

    def get_ratio(image, width,height, min_or_max = :min)
      width_ratio = width.to_f / image.width
      height_ratio = height.to_f / image.height
      [width_ratio, height_ratio].send(min_or_max)
    end
  end
end
