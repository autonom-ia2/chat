json.payload do
  json.array! @brand_kits, partial: 'brand_kit', as: :brand_kit
end
json.meta do
  json.archived_count @archived_count
end
