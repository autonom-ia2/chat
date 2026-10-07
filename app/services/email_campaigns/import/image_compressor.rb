# Makes an imported image fit an e-mail (#1099, delivery B): at most 1200 px wide and 200 KB, and served without the
# metadata it came with (camera, place, author: the copy lives at a public address). The image is first turned upright
# (EXIF orientation), since the metadata that told how to show it is dropped. A PNG or JPEG that already fits is saved
# again with `strip` (JPEG at a high quality); a GIF that fits is kept byte for byte (GIF carries no EXIF, and re-saving
# an animated one would lose its frames); anything else is resized with image_processing (libvips, whose untrusted loaders the
# production image blocks) and saved as JPEG — PNG when it has transparency — trying smaller widths and qualities until
# it fits. An animated GIF that had to be resized keeps only its first frame, and the output says so
# (`animation_lost`) for the report. WebP becomes JPEG/PNG, since Outlook does not show it. Images above MAX_PIXELS are
# refused before decoding (decompression bomb). Raises Unfit when nothing fits.
module EmailCampaigns::Import::ImageCompressor
  MAX_BYTES = 200 * 1024
  MAX_WIDTH = 1200
  MAX_PIXELS = 40_000_000
  WIDTHS = [1200, 900, 600, 400].freeze
  JPEG_QUALITIES = [85, 72, 60, 48].freeze
  KEPT_JPEG_QUALITY = 92
  KEPT_TYPES = %w[image/png image/jpeg image/gif].freeze
  EXTENSIONS = { 'image/png' => 'png', 'image/jpeg' => 'jpg', 'image/gif' => 'gif' }.freeze

  Output = Data.define(:bytes, :content_type, :extension, :compressed, :animation_lost) do
    def initialize(bytes:, content_type:, extension:, compressed:, animation_lost: false)
      super
    end
  end

  class Unfit < StandardError; end

  module_function

  # libvips is loaded on the first use (not when the class loads), so the rest of the import works where it is absent.
  def call(bytes, content_type)
    require 'image_processing/vips'
    image = Vips::Image.new_from_buffer(bytes, '')
    raise Unfit, 'too many pixels' if image.width * image.height > MAX_PIXELS

    return keep(bytes, content_type) if content_type == 'image/gif' && fits?(bytes, content_type, image)

    output = fit(image.autorot, bytes, content_type)
    content_type == 'image/gif' && pages(image) > 1 ? output.with(animation_lost: true) : output
  rescue Vips::Error
    raise Unfit, 'unreadable image'
  end

  def fit(upright, bytes, content_type)
    kept = resave(upright, content_type) if fits?(bytes, content_type, upright)
    kept || shrink(upright) || raise(Unfit, 'still above the size ceiling')
  end

  def pages(image)
    image.get_typeof('n-pages').zero? ? 1 : image.get('n-pages')
  end

  def keep(bytes, content_type)
    Output.new(bytes: bytes, content_type: content_type, extension: EXTENSIONS.fetch(content_type), compressed: false)
  end

  def fits?(bytes, content_type, image)
    KEPT_TYPES.include?(content_type) && bytes.bytesize <= MAX_BYTES && image.width <= MAX_WIDTH
  end

  # The same PNG or JPEG without its metadata, or nil when saving it again does not fit (the shrinking path takes over).
  def resave(image, content_type)
    data = case content_type
           when 'image/png' then image.pngsave_buffer(compression: 9, strip: true)
           when 'image/jpeg' then image.jpegsave_buffer(Q: KEPT_JPEG_QUALITY, strip: true, optimize_coding: true)
           end
    return if data.nil? || data.bytesize > MAX_BYTES

    Output.new(bytes: data, content_type: content_type, extension: EXTENSIONS.fetch(content_type), compressed: false)
  end

  def shrink(image)
    widths(image.width).each do |width|
      resized = ImageProcessing::Vips.source(image).resize_to_limit(width, nil).call(save: false)
      output = image.has_alpha? ? png(resized) : nil
      output ||= jpeg(image.has_alpha? ? resized.flatten(background: [255, 255, 255]) : resized)
      return output if output
    end
    nil
  end

  def widths(original)
    limit = [original, MAX_WIDTH].min
    ([limit] + WIDTHS.select { |width| width < limit }).uniq
  end

  def png(image)
    data = image.pngsave_buffer(compression: 9, strip: true)
    Output.new(bytes: data, content_type: 'image/png', extension: 'png', compressed: true) if data.bytesize <= MAX_BYTES
  end

  def jpeg(image)
    JPEG_QUALITIES.each do |quality|
      data = image.jpegsave_buffer(Q: quality, strip: true, optimize_coding: true, interlace: true)
      return Output.new(bytes: data, content_type: 'image/jpeg', extension: 'jpg', compressed: true) if data.bytesize <= MAX_BYTES
    end
    nil
  end
end
