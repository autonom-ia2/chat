json.payload do
  json.array! @brand_kits, partial: 'brand_kit', as: :brand_kit
end
