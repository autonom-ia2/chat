# A chave da conversa com a cara do canal (#1702). Desligada, o recebimento do WhatsApp fica igual ao do Chatwoot:
# nenhum prepend do recebimento grava marca, reação, edição ou pedido.
module ConversaCanal::Pele
  FLAG = 'conversa_cara_do_canal'.freeze
  # Mensagem que saiu de modelo ou de campanha: o corpo foi preenchido para aquele cliente e os botões não vão juntos.
  # Não ganha prévia de link no painel e não pode ser encaminhada (decisão do Rodrigo, 16/10).
  MARCAS_DE_MODELO = %w[template_params campaign_id whatsapp_api_campaign_id campaign_template_name].freeze

  module_function

  def ligada?(account)
    account&.feature_enabled?(FLAG) || false
  end

  def modelo_ou_campanha?(message)
    message.additional_attributes.to_h.values_at(*MARCAS_DE_MODELO).any?(&:present?)
  end
end
