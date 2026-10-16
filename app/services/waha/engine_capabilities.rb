# O que um motor WAHA com o conector customizado sabe mandar nativo (chat#1709, fase 2).
#
# Só motores listados em ENV `WAHA_RICH_NATIVE_ENGINES` (URLs separadas por vírgula; vazia por padrão = tudo sai em
# texto). A caixa WAHA comum usa o motor cuja URL (com a barra final) é o começo do `webhook_url` dela. O webhook da
# caixa sempre tem caminho (`<motor>/webhooks/chatwoot/...`): uma `webhook_url` igual à raiz do motor, sem barra, não
# casa com nenhum motor e a caixa fica em texto.
# O motor declara a capacidade em `GET <motor>/api/server/version`, no campo `autonomia.rich_native`:
#   { "autonomia": { "patch": "c2y-rich-1", "rich_native": ["options", "location", "contact"], "list_reply": true } }
# `options` só conta com `list_reply: true` (o conector devolve a escolha do cliente em `waha_list_reply`).
#
# NADA aqui faz HTTP na criação de mensagem nem na lista de conversas: `types` só LÊ o cache. Quem consulta o motor é
# o Waha::EngineCapabilitiesRefreshJob (cron a cada minuto), que grava o resultado por CACHE_TTL. Sem valor no cache
# (motor nunca lido, ou falhando há mais de CACHE_TTL) = nenhum tipo: tudo sai em texto.
# Todos os motores da lista usam a mesma chave do WAHA (`WAHA_API_KEY`, Waha::Config.api_key); motor com outra chave
# responde 401/403, que vai ao rastreador de erros com o nome do motor.
module Waha::EngineCapabilities
  ENV_KEY = 'WAHA_RICH_NATIVE_ENGINES'.freeze
  VERSION_PATH = 'api/server/version'.freeze
  CACHE_TTL = 10.minutes
  # O HTTParty não tem tempo total: estes são o de conexão e o de leitura, cada um.
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3
  UNAUTHORIZED = [401, 403].freeze

  class Unauthorized < StandardError; end

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

  # Os tipos (`Waha::RichNative::KINDS`) que o motor manda nativo, do cache. Sem valor = nenhum.
  def types(engine)
    return [] if engine.blank?

    Array(Rails.cache.read(cache_key(engine)))
  end

  def cache_key(engine)
    "waha/engine_capabilities/#{engine}"
  end

  # Lê o motor e grava por CACHE_TTL (inclusive "nenhum tipo", resposta válida de um motor sem o conector). Falha (sem
  # resposta, erro, status fora de 2xx) não grava: o valor anterior segue até expirar. Devolve os tipos lidos ou nil.
  def refresh!(engine)
    response = HTTParty.get("#{engine}#{VERSION_PATH}", headers: { 'X-Api-Key' => Waha::Config.api_key.to_s },
                                                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
    return refused(engine, response.code) unless response.success?

    types = declared(response.parsed_response)
    Rails.cache.write(cache_key(engine), types, expires_in: CACHE_TTL)
    types
  rescue StandardError => e
    Rails.logger.warn("[waha] engine capabilities unavailable engine=#{engine} #{e.class}")
    nil
  end

  # 401/403: o motor não aceita a chave do WAHA (todos os motores da lista precisam da mesma). Vai ao rastreador.
  def refused(engine, status)
    Rails.logger.warn("[waha] engine capabilities refused engine=#{engine} status=#{status}")
    if UNAUTHORIZED.include?(status)
      ChatwootExceptionTracker.new(Unauthorized.new("WAHA engine #{engine} answered #{status} to the shared WAHA_API_KEY"))
                              .capture_exception
    end
    nil
  end

  def declared(body)
    autonomia = body.is_a?(Hash) ? body['autonomia'] : nil
    return [] unless autonomia.is_a?(Hash) && autonomia['rich_native'].is_a?(Array)

    types = Waha::RichNative::KINDS & autonomia['rich_native'].map(&:to_s)
    autonomia['list_reply'] == true ? types : types - ['options']
  end
end
