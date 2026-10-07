# Keeps one image of an import (#1099): the compressed bytes become a blob attached to the import and served at a
# permanent public address (PublicUrl). The import job uses it for every copied image (delivery B) and the screen for
# the image the person sends in place of one that did not come (delivery C), so both end up owned by the import —
# the only images SaveCheck accepts.
module EmailCampaigns::Import::ImageUpload
  module_function

  def call(import, output, name)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(output.bytes), filename: "#{name}.#{output.extension}",
                                                  content_type: output.content_type, identify: false)
    import.images.attach(blob)
    EmailCampaigns::Import::PublicUrl.for(blob)
  end
end
