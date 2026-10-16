# O que um motor WAHA com o conector customizado sabe mandar nativo (chat#1709, fase 2).
#
# Só motores listados em ENV `WAHA_RICH_NATIVE_ENGINES` (URLs separadas por vírgula; vazia por padrão = tudo sai em
# texto). A caixa WAHA comum usa o motor cuja URL (com a barra final) é o começo do `webhook_url` dela.
# O motor declara a capacidade em `GET <motor>/api/server/version`, no campo `autonomia.rich_native`:
#   { "autonomia": { "patch": "c2y-rich-1", "rich_native": ["options", "location", "contact"], "list_reply": true } }
# `options` só conta com `list_reply: true` (o conector devolve a escolha do cliente em `waha_list_reply`).
# Erro, sem resposta ou campo ausente = nenhum tipo. Resultado guardado por CACHE_TTL (inclusive o vazio).
# A chave do motor é a mesma do resto do WAHA (Waha::Config.api_key): motores com chaves diferentes não são suportados.
module Waha::EngineCapabilities
  ENV_KEY = 'WAHA_RICH_NATIVE_ENGINES'.freeze
  VERSION_PATH = 'api/server/version'.freeze
  CACHE_TTL = 60.seconds
  TIMEOUT = 3

  module_function

  # As URLs dos motores listados, cada uma com a barra final.
  def engines
    ENV.fetch(ENV_KEY, '').split(',').map(&:strip).compact_blank.map { |url| "#{url.chomp('/')}/" }
  end

  # O motor listado que serve este `webhook_url`, ou nil.
  def engine_for(webhook_url)
    url = webhook_url.to_s
    engines.find { |engine| url.start_with?(engine) }
  end

  # Os tipos (`Waha::RichNative::KINDS`) que o motor manda nativo.
  def types(engine)
    return [] if engine.blank?

    Rails.cache.fetch("waha/engine_capabilities/#{engine}", expires_in: CACHE_TTL) { fetch_types(engine) }
  end

  def fetch_types(engine)
    response = HTTParty.get("#{engine}#{VERSION_PATH}", headers: { 'X-Api-Key' => Waha::Config.api_key.to_s },
                                                        timeout: TIMEOUT)
    return [] unless response.success?

    declared(response.parsed_response)
  rescue StandardError => e
    Rails.logger.warn("[waha] engine capabilities unavailable engine=#{engine} #{e.class}")
    []
  end

  def declared(body)
    autonomia = body.is_a?(Hash) ? body['autonomia'] : nil
    return [] unless autonomia.is_a?(Hash) && autonomia['rich_native'].is_a?(Array)

    types = Waha::RichNative::KINDS & autonomia['rich_native'].map(&:to_s)
    autonomia['list_reply'] == true ? types : types - ['options']
  end
end
