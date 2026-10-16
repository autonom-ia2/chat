# `waha_revoke` (chat#1709, rodada 2): o cliente apagou uma mensagem "para todos", { revoked_wa_id, from_me }. Na main
# vira uma nota privada e a original continua sem marca. Com a flag, a original ganha `deleted_by_contact_at` (ISO
# 8601) e o conteúdo fica INTACTO, como prova (decisão do Rodrigo): nunca `deleted`, que esconde o conteúdo. A gravação
# não vai ao conector (Waha::RichNative::SilentUpdate). Apagada no celular da empresa (from_me): fica a nota da main.
# A nota da main CONTINUA visível para a equipe, só ganha `revoke_applied_to` (revisão da rodada 2): quem mostra o selo
# "apagada pelo cliente" na original é a tela do Frontend geral (#1702, PR #1724), que ainda não está no ar. Esconder a
# nota antes dela faria a equipe e a IA perderem o aviso de que o cliente apagou. Quando a tela estiver no ar, a nota
# passa a atividade escondida (Waha::RichNative::Inbound.hide!) em PR próprio.
module Waha::RichNative::Inbound::Revoke
  KEY = 'deleted_by_contact_at'.freeze
  APPLIED_KEY = 'revoke_applied_to'.freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash) && data['from_me'] != true

    target = Waha::RichNative::Inbound.target_of(message, message_type: :incoming)
    return if target.nil?

    mark!(target)
    message.content_attributes = message.content_attributes.to_h.merge(APPLIED_KEY => target.id)
  end

  def mark!(target)
    target.with_lock do
      next if target.content_attributes.to_h[KEY].present?

      target.content_attributes = target.content_attributes.to_h.merge(KEY => Time.current.iso8601)
      target.save!(validate: false)
    end
  end
end
