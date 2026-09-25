# País em que a Prospecção busca no Google, por conta (#677). Lista e mapa país-idioma portados do Orth
# (lib/busca/search-country.ts). O país muda os dados do Google (regionCode, languageCode, autocomplete e telefone),
# não o idioma da tela.
module Autonomia::Prospecting::SearchCountry
  DEFAULT = 'BR'.freeze

  LANGUAGE_CODES = {
    'BR' => 'pt-BR',
    'PT' => 'pt-PT',
    'US' => 'en',
    'FR' => 'fr',
    'ES' => 'es',
    'DE' => 'de',
    'IT' => 'it',
    'GB' => 'en',
    'MX' => 'es',
    'AR' => 'es',
    'CL' => 'es',
    'CO' => 'es',
    'PE' => 'es',
    'EC' => 'es',
    'PY' => 'es',
    'UY' => 'es',
    'AT' => 'de',
    'IE' => 'en',
    'IN' => 'en'
  }.freeze

  ALLOWED = LANGUAGE_CODES.keys.freeze

  module_function

  # Código ISO 3166 alfa-2 da lista, ou nil.
  def normalize(value)
    code = value.to_s.strip.upcase
    ALLOWED.include?(code) ? code : nil
  end

  def language_code(country)
    LANGUAGE_CODES.fetch(normalize(country) || DEFAULT)
  end
end
