# `waha_revoke` (chat#1709, rodada 2): uma mensagem apagada "para todos", { revoked_wa_id, from_me }. O conector cria
# uma nota privada ("Esta mensagem foi excluída no WhatsApp", com a miniatura quebrada quando era foto). Na main ela é
# tudo o que fica. Com a flag:
# - apagada pelo CLIENTE: a original ganha `deleted_by_contact_at` (ISO 8601) com o conteúdo INTACTO, como prova
#   (decisão do Rodrigo: nunca `deleted`, que esconde o conteúdo; a gravação não vai ao conector,
#   Waha::RichNative::SilentUpdate), e a nota do conector vira atividade escondida (`c2y_hidden`, `revoke_applied_to`):
#   a informação já está na bolha da original (teste real, 17/10/2026: a nota duplicava o aviso);
# - apagada pela EMPRESA (from_me): quando a original nossa já está marcada `deleted` (apagada pelo painel, que pediu ao
#   motor), a nota também vira atividade escondida. Apagada direto no celular da empresa, sem a marca na original: a
#   nota fica, como na main (é o único aviso).
# Sem a original (nota, atividade, de outro contato): a nota fica, como na main.
module Waha::RichNative::Inbound::Revoke
  KEY = 'deleted_by_contact_at'.freeze
  APPLIED_KEY = 'revoke_applied_to'.freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash)
    return apply_from_me(message) if data['from_me'] == true

    target = Waha::RichNative::Inbound.target_of(message, message_type: :incoming)
    return if target.nil?

    mark!(target)
    Waha::RichNative::Inbound.hide!(message, 'revoke', APPLIED_KEY => target.id)
  end

  # A original nossa já apagada pelo painel (`deleted`): o Waha::RichNative::Inbound.target_of não a devolve (ele recusa
  # as apagadas), então a busca é a mesma, só que pedindo a apagada.
  def apply_from_me(message)
    target = deleted_outgoing(message)
    Waha::RichNative::Inbound.hide!(message, 'revoke_business', APPLIED_KEY => target.id) if target
  end

  def deleted_outgoing(message)
    target_id = Waha::RichNative::Inbound::ReplyTarget.target_id(message)
    contact_id = message.conversation&.contact_id
    return if target_id.blank? || contact_id.nil?

    target = Message.joins(:conversation).where(conversations: { contact_id: contact_id }, private: false)
                    .find_by(id: target_id, inbox_id: message.inbox_id, message_type: :outgoing)
    target if target&.content_attributes.to_h['deleted']
  end

  def mark!(target)
    target.with_lock do
      next if target.content_attributes.to_h[KEY].present?

      target.content_attributes = target.content_attributes.to_h.merge(KEY => Time.current.iso8601)
      target.save!(validate: false)
    end
  end
end
