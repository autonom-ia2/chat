# A chave da conversa com a cara do canal (#1702). Desligada, o recebimento do WhatsApp fica igual ao do Chatwoot:
# nenhum prepend do recebimento grava marca, reação, edição ou pedido.
module ConversaCanal::Pele
  FLAG = 'conversa_cara_do_canal'.freeze

  module_function

  def ligada?(account)
    account&.feature_enabled?(FLAG) || false
  end
end
