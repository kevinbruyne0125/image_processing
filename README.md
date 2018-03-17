# ImageProcessing

Provides higher-level image processing functionality that is commonly needed
when accepting user uploads. Supports processing with [VIPS] and
[ImageMagick]/[GraphicsMagick].

The goal of this project is to have a single place where common image
processing helper methods are maintained, instead of Paperclip, CarrierWave,
Refile, Dragonfly and ActiveStorage each implementing their own versions.

## Installation

```rb
gem "image_processing"
```

## Usage

Processing is performed through `ImageProcessing::Vips` or
`ImageProcessing::MiniMagick` modules. Both modules share the same chainable
API for defining the processing pipeline:

```rb
require "image_processing/mini_magick"

processed = ImageProcessing::MiniMagick
  .source(file)
  .auto_orient
  .resize_to_limit(400, 400)
  .convert("png")
  .call

processed #=> #<File:/var/folders/.../image_processing-vips20180316-18446-1j247h6.png>
```

This allows easy branching when generating multiple derivatives:

```rb
require "image_processing/vips"

pipeline = ImageProcessing::Vips
  .source(file)
  .autorot
  .convert("png")

large  = pipeline.resize_to_limit!(800, 800)
medium = pipeline.resize_to_limit!(500, 500)
small  = pipeline.resize_to_limit!(300, 300)
```

The processing is executed on `#call` or when a processing method is called
with a bang (`!`).

```rb
processed = ImageProcessing::Vips
  .convert("png")
  .resize_to_limit(400, 400)
  .call(image)

# OR

processed = ImageProcessing::Vips
  .source(image) # declare source image
  .convert("png")
  .resize_to_limit(400, 400)
  .call

# OR

processed = ImageProcessing::Vips
  .source(image)
  .convert("png")
  .resize_to_limit!(400, 400) # bang method
```

The source image needs to be an object that responds to `#path`, and the
processing result is a `Tempfile` object.

```rb
pipeline = ImageProcessing::Vips.source(image)

tempfile = pipeline.call
tempfile #=> #<Tempfile ...>

vips_image = pipeline.call(save: false)
vips_image #=> #<Vips::Image ...>
```

## ruby-vips

The `ImageProcessing::Vips` module contains processing macros that use the
[ruby-vips] gem, which you need to install:

```rb
# Gemfile
gem "ruby-vips", "~> 2.0"
```

Note that you'll need to have [libvips] 8.6 or higher installed; see
the [installation instructions][libvips installation] for more details.

### Methods

#### `.valid_image?`

Returns true if the image is processable, and false if it's corrupted or not
supported by libvips.

```rb
ImageProcessing::Vips.valid_image?(normal_image)    #=> true
ImageProcessing::Vips.valid_image?(corrupted_image) #=> false
```

#### `#resize_to_limit`

Downsizes the image to fit within the specified dimensions while retaining the
original aspect ratio. Will only resize the image if it's larger than the
specified dimensions.

```rb
pipeline = ImageProcessing::Vips.source(image) # 600x800

result = pipeline.resize_to_limit!(400, 400)

Vips::Image.new_from_file(result.path).size #=> [300, 400]
```

It's possible to omit one dimension, in which case the image will be resized
only by the provided dimension.

```rb
pipeline.resize_to_limit!(400, nil)
# or
pipeline.resize_to_limit!(nil, 400)
```

Any additional options are forwarded to [`Vips::Image#thumbnail_image`]:

```rb
pipeline.resize_to_limit!(400, 400, linear: true)
```

See [`vips_thumbnail()`] for more details.

#### `#resize_to_fit`

Resizes the image to fit within the specified dimensions while retaining the
original aspect ratio. Will downsize the image if it's larger than the
specified dimensions or upsize if it's smaller.

```rb
pipeline = ImageProcessing::Vips.source(image) # 600x800

result = pipeline.resize_to_fit!(400, 400)

Vips::Image.new_from_file(result.path).size #=> [300, 400]
```

It's possible to omit one dimension, in which case the image will be resized
only by the provided dimension.

```rb
pipeline.resize_to_fit!(400, nil)
# or
pipeline.resize_to_fit!(nil, 400)
```

Any additional options are forwarded to [`Vips::Image#thumbnail_image`]:

```rb
pipeline.resize_to_fit!(400, 400, linear: true)
```

See [`vips_thumbnail()`] for more details.

#### `#resize_to_fill`

Resizes the image to fill the specified dimensions while retaining the original
aspect ratio. If necessary, will crop the image in the larger dimension.

```rb
pipeline = ImageProcessing::Vips.source(image) # 600x800

result = pipeline.resize_to_fill!(400, 400)

Vips::Image.new_from_file(result.path).size #=> [400, 400]
```

Any additional options are forwarded to [`Vips::Image#thumbnail_image`]:

```rb
pipeline.resize_to_fill!(400, 400, crop: :attention) # smart crop
```

See [`vips_thumbnail()`] for more details.

#### `#resize_and_pad`

Resizes the image to fit within the specified dimensions while retaining the
original aspect ratio. If necessary, will pad the remaining area with the given
color.

```rb
pipeline = ImageProcessing::Vips.source(image) # 600x800

result = pipeline.resize_and_pad!(400, 400)

Vips::Image.new_from_file(result.path).size #=> [400, 400]
```

It accepts `:background` for specifying the background [color] that will be
used for padding (defaults to black).

```rb
pipeline.resize_and_pad!(400, 400, color: "RoyalBlue")
# or
pipeline.resize_and_pad!(400, 400, color: [65, 105, 225])
```

It also accepts `:gravity` for specifying the [direction] where the source
image will be positioned (defaults to `"centre"`).

```rb
pipeline.resize_and_pad!(400, 400, gravity: "north-west")
```

Any additional options are forwarded to [`Vips::Image#thumbnail_image`]:

```rb
pipeline.resize_to_fill!(400, 400, linear: true)
```

See [`vips_thumbnail()`] and [`vips_gravity()`] for more details.

#### `#convert`

Specifies the output format.

```rb
pipeline = ImageProcessing::Vips.source(image)

result = pipeline.convert!("png")

File.extname(result.path)
#=> ".png"
```

By default the original format is retained when writing the image to a file. If
the source file doesn't have a file extension, the format will default to JPEG.

#### `#method_missing`

Any unknown methods will be delegated to [`Vips::Image`].

```rb
ImageProcessing::Vips
  .crop(0, 0, 300, 300)
  .invert
  .set("icc-profile-data", custom_profile)
  .gaussblur(2)
  # ...
```

#### `#custom`

Calls the provided block with the intermediary `Vips::Image` object. The return
value of the provided block must be a `Vips::Image` object.

```rb
ImageProcessing::Vips
  .source(file)
  .resize_to_limit(400, 400)
  .custom { |image| image + image.invert }
  .call
```

#### `#loader`

Specifies options that will be forwarded to [`Vips::Image.new_from_file`].

```rb
ImageProcessing::Vips
  .loader(access: :sequential)
  .resize_to_limit(400, 400)
  .call(source)
```

See [`vips_jpegload()`], [`vips_pngload()`] etc. for more details on
format-specific load options.

If you would like to have more control over loading, you can load the image
directly using `Vips::Image`, and just pass the `Vips::Image` object as the
source file.

```rb
vips_image = Vips::Image.magickload(file.path, n: -1)

ImageProcessing::Vips
  .source(vips_image)
  # ...
```

#### `#saver`

Specifies options that will be forwarded to [`Vips::Image#write_to_file`].

```rb
ImageProcessing::Vips
  .saver(Q: 100)
  .resize_to_limit(400, 400)
  .call(source)
```

See [`vips_jpegsave()`], [`vips_pngsave()`] etc. for more details on
format-specific save options.

If you would like to have more control over saving, you can call `#call(save:
false)` to get the `Vips::Image` object, and call the saver on it directly.

```rb
vips_image = ImageProcessing::Vips
  .resize_to_limit(400, 400)
  .call(save: false)

vips_image.write_to_file("/path/to/destination", **options)
```

## MiniMagick

The `ImageProcessing::MiniMagick` module contains processing methods that use
the [MiniMagick] gem, which you need to install:

```rb
# Gemfile
gem "mini_magick", "~> 4.0"
```

### Methods

#### `.valid_image?`

Returns true if the image is processable, and false if it's corrupted or not
supported by imagemagick.

```rb
ImageProcessing::MiniMagick.valid_image?(normal_image)    #=> true
ImageProcessing::MiniMagick.valid_image?(corrupted_image) #=> false
```

#### `#resize_to_limit`

Downsizes the image to fit within the specified dimensions while retaining the
original aspect ratio. Will only resize the image if it's larger than the
specified dimensions.

```rb
pipeline = ImageProcessing::MiniMagick.source(image) # 600x800

result = pipeline.resize_to_limit!(400, 400)

MiniMagick::Image.new(result.path).dimensions #=> [300, 400]
```

It's possible to omit one dimension, in which case the image will be resized
only by the provided dimension.

```rb
pipeline.resize_to_limit!(400, nil)
# or
pipeline.resize_to_limit!(nil, 400)
```

#### `#resize_to_fit`

Resizes the image to fit within the specified dimensions while retaining the
*original aspect ratio. Will downsize the image if it's larger than the
specified dimensions or upsize if it's smaller.

```rb
pipeline = ImageProcessing::MiniMagick.source(image) # 600x800

result = pipeline.resize_to_fit!(400, 400)

MiniMagick::Image.new(result.path).dimensions #=> [300, 400]
```

It's possible to omit one dimension, in which case the image will be resized
only by the provided dimension.

```rb
pipeline.resize_to_fit!(400, nil)
# or
pipeline.resize_to_fit!(nil, 400)
```

#### `#resize_to_fill`

Resizes the image to fill the specified dimensions while retaining the original
aspect ratio. If necessary, will crop the image in the larger dimension.

```rb
pipeline = ImageProcessing::MiniMagick.source(image) # 600x800

result = pipeline.resize_to_fill!(400, 400)

MiniMagick.new(result.path).dimensions #=> [400, 400]
```

It accepts `:gravity` for specifying the [gravity] to apply while cropping
(defaults to `"Center"`).

```rb
pipeline.resize_to_fill!(400, 400, gravity: "NorthWest")
```

#### `#resize_and_pad`

Resizes the image to fit within the specified dimensions while retaining the
original aspect ratio. If necessary, will pad the remaining area with the given
color.

```rb
pipeline = ImageProcessing::MiniMagick.source(image) # 600x800

result = pipeline.resize_and_pad!(400, 400)

MiniMagick::Image.new(result.path).dimensions #=> [400, 400]
```

It accepts `:background` for specifying the background [color] that will be
used for padding (defaults to transparent/white).

```rb
pipeline.resize_and_pad!(400, 400, color: "RoyalBlue")
```

It accepts `:gravity` for specifying the [gravity] to apply while cropping
(defaults to `"Center"`).

```rb
pipeline.resize_and_pad!(400, 400, gravity: "NorthWest")
```

#### `#convert`

Specifies the output format.

```rb
pipeline = ImageProcessing::MiniMagick.source(image)

result = pipeline.convert!("png")

File.extname(result.path)
#=> ".png"
```

By default the original format is retained when writing the image to a file. If
the source file doesn't have a file extension, the format will default to JPEG.

#### `#method_missing`

Any unknown methods will be appended directly as `convert`/`magick` options.

```rb
ImageProcessing::MiniMagick
  .quality(100)
  .crop("300x300+0+0")
  .resample("300x300")
  # ...
```

#### `#append`

Appends given values directly as arguments to the `convert` command.

```rb
ImageProcessing::MiniMagick
  .append("-quality", 100)
  .append("-flip")
  # ...
```

#### `#loader`

It accepts the following options:

* `:page` -- specific page(s) that should be loaded
* `:geometry` -- geometry that should be applied when loading
* `:fail` -- whether processing should fail on warnings

```rb
ImageProcessing::MiniMagick.source(document).loader(page: 0).convert!("png")
# convert input.pdf[0] output.png

ImageProcessing::MiniMagick.source(image).loader(geometry: "300x300").convert!("png")
# convert input.jpg[300x300] output.png

ImageProcessing::MiniMagick.source(image).loader(fail: true).convert!("png")
# convert -regard-warnings input.jpg output.png (raises MiniMagick::Error in case of warnings)
```

## Contributing

Test suite requires `imagemagick`, `graphicsmagick` and `libvips` to be
installed. On Mac OS you can install them with Homebrew:

```
$ brew install imagemagick graphicsmagick vips
```

Afterwards you can run tests with

```
$ rake test
```

## Credits

The `ImageProcessing::MiniMagick` functionality was extracted from
[refile-mini_magick].

## License

[MIT](LICENSE.txt)

[ImageMagick]: https://www.imagemagick.org
[GraphicsMagick]: http://www.graphicsmagick.org
[VIPS]: http://jcupitt.github.io/libvips/
[MiniMagick]: https://github.com/minimagick/minimagick
[ruby-vips]: https://github.com/jcupitt/ruby-vips
[libvips]: https://github.com/jcupitt/libvips
[libvips installation]: https://github.com/jcupitt/libvips/wiki#building-and-installing
[refile-mini_magick]: https://github.com/refile/refile-mini_magick
[`Vips::Image`]: http://www.rubydoc.info/gems/ruby-vips/Vips/Image
[`Vips::Image.new_from_file`]: http://www.rubydoc.info/gems/ruby-vips/Vips/Image#new_from_file-class_method
[`Vips::Image#write_to_file`]: http://www.rubydoc.info/gems/ruby-vips/Vips/Image#write_to_file-instance_method
[`Vips::Image#thumbnail_image`]: http://www.rubydoc.info/gems/ruby-vips/Vips/Image#thumbnail_image-instance_method
[`Vips::Image#set`]: http://www.rubydoc.info/gems/ruby-vips/Vips/Image#set-instance_method
[`Vips::Image#set_type`]: http://www.rubydoc.info/gems/ruby-vips/Vips/Image#set_type-instance_method
[`vips_thumbnail()`]: https://jcupitt.github.io/libvips/API/current/libvips-resample.html#vips-thumbnail
[`vips_gravity()`]: http://jcupitt.github.io/libvips/API/current/libvips-conversion.html#vips-gravity
[`vips_jpegload()`]: https://jcupitt.github.io/libvips/API/current/VipsForeignSave.html#vips-jpegload
[`vips_pngload()`]: https://jcupitt.github.io/libvips/API/current/VipsForeignSave.html#vips-pngload
[`vips_jpegsave()`]: https://jcupitt.github.io/libvips/API/current/VipsForeignSave.html#vips-jpegsave
[`vips_pngsave()`]: https://jcupitt.github.io/libvips/API/current/VipsForeignSave.html#vips-pngsave
[color]: https://www.imagemagick.org/script/color.php#color_names
[direction]: http://jcupitt.github.io/libvips/API/current/libvips-conversion.html#VipsCompassDirection
[gravity]: https://www.imagemagick.org/script/command-line-options.php#gravity
