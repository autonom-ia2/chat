# A regra única de "dá para reagir a esta mensagem" no WhatsApp (#1702 e chat#1709), usada pela reação da pele
# (ConversaCanal::ReacaoDoAtendente) e pela do painel na caixa WAHA (Waha::RichNative::MessageActions.react!):
# mensagem da conversa que foi ao cliente ou veio dele. Fora: nota, atividade, modelo, apagada (pelo painel ou pelo
# cliente), falhada (nunca chegou; na caixa WAHA, gravar nela mandaria o `external_error` de volta ao conector, que o
# lê como pedido de reenvio) e o aviso de visualização única (não é mensagem do cliente no WhatsApp).
module Whatsapp::MensagemReagivel
  MARCAS_QUE_TIRAM = %w[deleted deleted_by_contact_at external_error].freeze
  # O aviso de visualização única que o aparelho vinculado não abre (gravado pelo recebimento do WAHA, chat#1709).
  # Lido pela chave, sem depender de quem a grava.
  AVISO_DE_VISUALIZACAO_UNICA = 'view_once_unavailable'.freeze

  module_function

  def reagivel?(message)
    da_conversa?(message) && !marcada?(message) && message.content_attributes.to_h[AVISO_DE_VISUALIZACAO_UNICA] != true
  end

  # Recebida ou enviada ao cliente: nem atividade, nem modelo, nem nota, nem falhada.
  def da_conversa?(message)
    (message.incoming? || message.outgoing?) && !message.private? && !message.failed?
  end

  def marcada?(message)
    message.content_attributes.to_h.values_at(*MARCAS_QUE_TIRAM).any?(&:present?)
  end
end
