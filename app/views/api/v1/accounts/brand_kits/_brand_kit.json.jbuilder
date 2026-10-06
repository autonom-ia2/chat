json.id brand_kit.id
json.name brand_kit.name
json.is_default brand_kit.is_default
json.archived_at brand_kit.archived_at
json.source_url brand_kit.source_url
json.appearance brand_kit.appearance_data
json.logo do
  if brand_kit.logo.attached?
    json.url url_for(brand_kit.logo)
    json.content_type brand_kit.logo.blob.content_type
    json.byte_size brand_kit.logo.blob.byte_size
  else
    json.nil!
  end
end
json.created_by_id brand_kit.created_by_id
json.created_at brand_kit.created_at
json.updated_at brand_kit.updated_at
