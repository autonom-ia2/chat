# frozen_string_literal: true

# Pacotes de tradução por conta (#1550). Camadas geral ← seguros ← seguros/<tipo>, por chave, com fallback ao geral.
# Interruptor por stack AUTONOMIA_PACOTES_ENABLED (desligado por padrão): desligado, toda conta tem camadas [].
# O canal da insurtech só fica guardado nesta fase; não vira camada.
#
# No servidor, as camadas valem só dentro de `with` (requisição da conta, e-mail, job que chamar o helper); fora dele o
# I18n devolve o catálogo base. O lookup fica em config/initializers/autonomia_segmentos_pacotes.rb.
module Autonomia::Segmentos::Pacotes
  ENV_KEY = 'AUTONOMIA_PACOTES_ENABLED'
  # Só "true" ou "1" ligam: valor digitado errado na stack deixa desligado (o padrão seguro).
  LIGADO = %w[true 1].freeze
  LOG_TAG = '[Autonomia::Segmentos::Pacotes]'

  def self.enabled?
    LIGADO.include?(ENV.fetch(ENV_KEY, '').to_s.strip.downcase)
  end

  def self.camadas(account)
    return [] if account.blank? || !enabled?

    escolha = Autonomia::Agents::Nicho.for(account)
    return [] unless escolha.nicho == Autonomia::Agents::Nicho::SEGUROS

    [escolha.nicho, "#{escolha.nicho}/#{escolha.perfil}"].freeze
  rescue StandardError => e
    # Só a classe: a mensagem pode carregar dado da conta.
    Rails.logger.warn("#{LOG_TAG} account=#{account&.id} #{e.class}; usando o geral")
    []
  end

  # Nome do pacote para o painel: "seguros.<tipo>" ou nil.
  def self.nome(account)
    camadas(account).last&.tr('/', '.')
  end

  def self.with(account)
    anterior = ActiveSupport::IsolatedExecutionState[AutonomiaPacotesI18nLookup::ESTADO]
    begin
      ActiveSupport::IsolatedExecutionState[AutonomiaPacotesI18nLookup::ESTADO] = camadas(account)
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[AutonomiaPacotesI18nLookup::ESTADO] = anterior
    end
  end

  def self.ativas
    ActiveSupport::IsolatedExecutionState[AutonomiaPacotesI18nLookup::ESTADO] || []
  end
end
