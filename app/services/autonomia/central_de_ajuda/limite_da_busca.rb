# Teto de gasto da Melhor resposta (#977). Conta só as chamadas reais ao Jev (resposta do cache não conta) e fica no
# serviço, com a identidade já autenticada, para valer qualquer que seja a grafia do pedido; o Rack::Attack é a
# primeira camada. Estourou, a busca fica sem Melhor resposta e a lista por palavras continua.
class Autonomia::CentralDeAjuda::LimiteDaBusca
  # Cada busca faz até duas chamadas (Melhor resposta e alternativa, #985): os tetos contam chamadas e foram
  # dobrados para manter as mesmas ~30 buscas por minuto por pessoa e ~2000 por dia por conta.
  POR_PESSOA_POR_MINUTO = ENV.fetch('CENTRAL_BUSCA_LIMITE_PESSOA_MINUTO', '60').to_i
  POR_CONTA_POR_DIA = ENV.fetch('CENTRAL_BUSCA_LIMITE_CONTA_DIA', '4000').to_i
  PREFIXO = 'autonomia/central_de_ajuda/limite_da_busca'.freeze

  def initialize(account:, account_user:)
    @account = account
    @account_user = account_user
  end

  def permitir?
    dentro?("pessoa/#{@account_user&.id}/#{Time.current.to_i / 60}", POR_PESSOA_POR_MINUTO, 2.minutes) &&
      dentro?("conta/#{@account.id}/#{Time.current.to_date}", POR_CONTA_POR_DIA, 2.days)
  end

  private

  # Sem contador (cache desligado ou fora do ar) o teto não bloqueia: a feature não some por causa do cache,
  # e o Rack::Attack continua valendo.
  def dentro?(chave, teto, validade)
    contagem = Rails.cache.increment("#{PREFIXO}/#{chave}", 1, expires_in: validade)
    contagem.nil? || contagem <= teto
  end
end
