# Os cabeçalhos que a ferramenta HTTP manda (`headers_config`): nome válido e nada que seja da plataforma.
module Autonomia::Agents::CabecalhosDaFerramenta
  extend ActiveSupport::Concern

  # Revisão adversarial do #1430: o `Host` do cadastro substitui o do endereço e levaria a chave guardada a outro site
  # sem passar pela regra de digitar de novo; os de encaminhamento fazem o mesmo em alguns proxies. Tamanho e conexão do
  # pedido também são da plataforma.
  CABECALHOS_DO_TRANSPORTE = %w[host x-forwarded-host forwarded x-original-url x-rewrite-url content-length transfer-encoding
                                connection].freeze

  # Revisão adversarial (3ª): cada cabeçalho é um render a mais por chamada.
  MAX_CABECALHOS = 20

  included do
    validate :validate_headers_config
  end

  private

  def validate_headers_config
    errors.add(:headers_config, "pode ter até #{MAX_CABECALHOS} cabeçalhos") if headers_config.size > MAX_CABECALHOS
    nomes_validos = headers_config.all? { |header| header['key'].to_s.match?(/\A[A-Za-z0-9-]+\z/) }
    errors.add(:headers_config, 'possui cabeçalhos inválidos') unless nomes_validos
    # #1430: a plataforma manda o dela em toda chamada (`ChaveDeIdempotencia`).
    if headers_config.any? { |header| header['key'].to_s.casecmp?('Idempotency-Key') }
      errors.add(:headers_config, 'não pode ter Idempotency-Key: a plataforma já manda um em toda chamada')
    end
    validate_cabecalhos_do_transporte
  end

  def validate_cabecalhos_do_transporte
    proibido = headers_config.find { |header| CABECALHOS_DO_TRANSPORTE.include?(header['key'].to_s.downcase) }
    errors.add(:headers_config, "não pode ter #{proibido['key']}: a plataforma decide para onde e como o pedido vai") if proibido
  end
end
