json.payload do
  json.array! @brand_kits, partial: 'brand_kit', as: :brand_kit
end
json.meta do
  json.archived_count @archived_count
  # Fontes que o e-mail carrega pelo Google Fonts ("Trocar" fonte); fora delas, o e-mail usa Arial.
  json.google_fonts BrandKits::GoogleFonts::FAMILIES.sort
end
