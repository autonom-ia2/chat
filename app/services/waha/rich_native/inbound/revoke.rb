# `waha_revoke` (chat#1709, rodada 2): o cliente apagou uma mensagem "para todos", { revoked_wa_id, from_me }. Na main
# vira uma nota privada e a original continua sem marca. Com a flag, a original ganha `deleted_by_contact_at` (ISO
# 8601) e o conteúdo fica INTACTO, como prova (decisão do Rodrigo): nunca `deleted`, que esconde o conteúdo. A nota
# vira atividade escondida (`revoke_applied_to`). Apagada no celular da empresa (from_me): fica a nota da main. A
# gravação não vai ao conector (Waha::RichNative::SilentUpdate).
module Waha::RichNative::Inbound::Revoke
  KEY = 'deleted_by_contact_at'.freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['from_me'] != true

    target = Waha::RichNative::Inbound.target_of(message, message_type: :incoming)
    return if target.nil?

    mark!(target)
    Waha::RichNative::Inbound.hide!(message, 'revoke', 'revoke_applied_to' => target.id)
  end

  def mark!(target)
    target.with_lock do
      next if target.content_attributes.to_h[KEY].present?

      target.content_attributes = target.content_attributes.to_h.merge(KEY => Time.current.iso8601)
      target.save!(validate: false)
    end
  end
end
