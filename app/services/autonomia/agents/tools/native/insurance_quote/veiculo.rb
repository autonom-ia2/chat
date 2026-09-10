# O VEÍCULO ANTES DA CONFERÊNCIA — entrega 2 do Agente de Cotação, termos 5 e 10.
#
# Separado da ferramenta pelo mesmo motivo de `Declaracao`, `Recusas` e `Envio`: é outro assunto
# (o que identifica o veículo e o que a consulta de placa acrescenta), e a classe já passava do
# teto de linhas ao ganhá-lo.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Veiculo
  extend ActiveSupport::Concern

  PLACA = 'vehicle.plate'.freeze
  IDENTIFICADORES_DO_VEICULO = %w[plate chassis fipeCode].freeze

  private

  # A entrada COM O TIPO DO VEÍCULO (entrega 2, termo 5): com placa e sem tipo, a consulta de
  # placa — gratuita — diz se é carro, moto ou caminhão, e é o tipo que liga as regras de moto e
  # caminhão na conferência. Falha na consulta não barra: a entrada segue sem o tipo, e o que sobra
  # é a conferência tardia do próprio envio.
  def entrada
    @entrada ||= com_veiculo(quote_input.to_h)
  end

  # Auto sem placa, chassi nem FIPE: não há veículo para cotar (termo 10).
  def sem_veiculo?
    return false unless quote_input.auto?

    veiculo = quote_input.to_h['vehicle'].to_h
    IDENTIFICADORES_DO_VEICULO.none? { |campo| veiculo[campo].present? }
  end

  def com_veiculo(dados)
    return dados unless quote_input.auto?

    veiculo = dados['vehicle'].to_h
    return dados if veiculo['plate'].blank? || veiculo['vehicleType'].present?

    dados.merge('vehicle' => veiculo.merge(lido_da_placa(veiculo)))
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] consulta de placa indisponivel account=#{account.id} #{e.class}")
    dados
  end

  # O que a consulta acrescenta: o tipo, e o ano do modelo quando o modelo não o escreveu.
  def lido_da_placa(veiculo)
    consulta = sessions.with_fresh_session do |session|
      connector.vehicle_lookup(provider: connection.provider, session: session, plate: veiculo['plate'])
    end
    { 'vehicleType' => consulta['vehicle_type'], 'modelYear' => veiculo['modelYear'] || consulta['model_year'] }.compact
  end
end
