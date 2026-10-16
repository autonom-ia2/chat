# Callback `after_update_commit` de Message (chat#1709, fase 3): apagar no painel apaga "para todos" no WhatsApp, numa
# caixa híbrida com a flag `whatsapp_rich_native`. O MessagesController#destroy do Chatwoot troca o conteúdo por
# "apagada" e `content_attributes` por { deleted: true }; aqui, depois do commit, a mensagem nossa (de saída, não nota)
# com id físico conhecido no `source_id` vai para o WhatsappHybrid::RichNative::RevokeJob, que pede ao motor. Sem
# prepend no controller (o Guia lê o formato da ação no método original). Nunca interrompe a gravação.
# Só na TRANSIÇÃO para apagada: depois do destroy, o primeiro ack (entregue/lida) grava `external_error: nil` e muda o
# `content_attributes` de novo; sem a transição, cada mudança dessas pediria outro "apagar para todos" ao motor.
class WhatsappHybrid::RichNative::RevokeOnDelete
  def self.after_commit(message)
    return unless revocable?(message)

    physical_id = WhatsappHybrid::RichNative::Quote.physical_id_of(message)
    WhatsappHybrid::RichNative::RevokeJob.perform_later(message.id, physical_id) if physical_id.present?
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] revoke on delete message=#{message.id} #{e.class}")
  end

  def self.revocable?(message)
    deleted_now?(message) &&
      message.outgoing? && !message.private? && WhatsappHybrid::RichNative.hybrid?(message.inbox) &&
      Waha::RichNative.enabled?(message.account)
  end

  # O `content_attributes` passou de não apagada para apagada neste commit.
  def self.deleted_now?(message)
    return false unless message.saved_change_to_content_attributes?

    before, after = message.saved_change_to_content_attributes
    after.to_h.stringify_keys['deleted'] == true && before.to_h.stringify_keys['deleted'] != true
  end
end
