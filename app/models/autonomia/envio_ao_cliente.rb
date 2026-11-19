# Uma mensagem de campanha ou de automação que saiu para o cliente (#3063, item 2): o contador do limite de mensagens
# por cliente. Quem grava é Autonomia::RitmoDeEnvio::Porteiro.contar!, depois do envio; o aviso de renovação da carteira
# não passa por ele. As linhas mais velhas que o maior período escolhível saem na varredura.
class Autonomia::EnvioAoCliente < ApplicationRecord
  self.table_name = 'envios_ao_cliente'

  ORIGENS = %w[campanha_whatsapp campanha_sms campanha_whatsapp_api campanha_email automacao_mensagem automacao_email].freeze

  belongs_to :account
  belongs_to :contact

  validates :origem, inclusion: { in: ORIGENS }
  validates :enviado_em, presence: true
end
