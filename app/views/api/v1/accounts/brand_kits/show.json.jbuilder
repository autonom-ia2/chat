json.payload do
  json.partial! 'brand_kit', brand_kit: @brand_kit
end
json.warnings @warnings || []
