# Callback `before_create` de Message (chat#1709, fases 2 e 3), o PRIMEIRO dos callbacks do contrato com o conector do
# WAHA. Vale em qualquer caminho de criação (API de mensagens, criação de conversa com mensagem, job, console), com ou
# sem a flag `whatsapp_rich_native`:
# - REQUEST_KEYS (pedido ao conector, só no payload do webhook da caixa): `waha_native` (Waha::RichNative::InboxWebhook),
#   `waha_text` e `waha_media_as_media` (Waha::RichNative::OutgoingHints). Guardadas, iriam ao conector e o motor mandaria
#   o que quem criou quisesse. Saem SEMPRE.
# - STORED_KEYS (o que o próprio chat2you grava ao transformar a volta do conector): `c2y_hidden`, `reactions`,
#   `edit_history` etc. Forjada, `c2y_hidden` esconderia do painel uma mensagem que foi ao cliente; `edit_history` e
#   `reactions` inventariam edição e reação. Saem SEMPRE na entrada. Quem grava essas chaves (Waha::RichNative::Inbound,
#   Waha::RichNative::PollVote) roda DEPOIS deste callback, ou marca a mensagem como escrita interna
#   (Waha::RichNative::InternalWrite, o voto do plano B do Híbrido, montado antes do `save!`).
# - INCOMING_ONLY_KEYS (`waha_list_reply`, `waha_poll_vote`): a escolha e o voto do cliente só existem em mensagem
#   RECEBIDA, que é como o conector as cria. Em qualquer outra, saem.
class Waha::RichNative::ContractGuard
  REQUEST_KEYS = %w[waha_native waha_text waha_media_as_media].freeze
  STORED_KEYS = %w[c2y_hidden reactions edit_history edited_at selected_options reaction_applied_to edit_applied_to
                   waha_call_summary waha_unknown_type].freeze
  INCOMING_ONLY_KEYS = %w[waha_list_reply waha_poll_vote].freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    dropped = dropped_keys(message).select { |key| attributes.key?(key) }
    message.content_attributes = attributes.except(*dropped) if dropped.any?
  end

  def self.dropped_keys(message)
    keys = REQUEST_KEYS
    keys += STORED_KEYS unless Waha::RichNative::InternalWrite.internal?(message)
    keys += INCOMING_ONLY_KEYS unless message.incoming?
    keys
  end
end
