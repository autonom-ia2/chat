# Callback `before_create` de Message (chat#1709, fases 2 e 3), o PRIMEIRO dos callbacks do contrato com o conector do
# WAHA. Vale em qualquer caminho de criação (API de mensagens, criação de conversa com mensagem, job, console), com ou
# sem a flag `whatsapp_rich_native`:
# - REQUEST_KEYS (pedido ao conector, só no payload do webhook da caixa): `waha_native` (Waha::RichNative::InboxWebhook),
#   `waha_text` e `waha_media_as_media` (Waha::RichNative::OutgoingHints). Guardadas, iriam ao conector e o motor mandaria
#   o que quem criou quisesse. Saem SEMPRE.
# - STORED_KEYS (o que o próprio chat2you grava ao transformar a volta do conector, no formato da tela do Frontend
#   geral, #1702): `c2y_hidden`, `reactions`, `edit_history`, `poll_votes` etc. Forjada, `c2y_hidden` esconderia do
#   painel uma mensagem que foi ao cliente; as outras inventariam reação, edição, voto, apagada ou citação. Saem SEMPRE
#   na entrada. Quem grava essas chaves (Waha::RichNative::Inbound e os módulos de gravação) roda DEPOIS deste callback,
#   ou marca a mensagem como escrita interna (Waha::RichNative::InternalWrite, o voto do plano B do Híbrido, montado
#   antes do `save!`). `shared_location` e `order` NÃO estão aqui: a Cloud os grava no próprio serviço de recebimento.
# - INCOMING_ONLY_KEYS (`waha_list_reply`, `waha_poll_vote`, `waha_event_response`): a escolha, o voto e a resposta ao
#   evento do cliente só existem em mensagem RECEBIDA, que é como o conector as cria. Em qualquer outra, saem.
class Waha::RichNative::ContractGuard
  REQUEST_KEYS = %w[waha_native waha_text waha_media_as_media].freeze
  STORED_KEYS = %w[
    c2y_hidden reactions edit_history edited_at selected_options poll_votes event_responses deleted_by_contact_at
    unsupported_kind waha_unknown_type waha_call_summary forwarded frequently_forwarded played_at quoted_message
    media_unavailable shared_contacts waha_ephemeral reaction_applied_to edit_applied_to poll_vote_applied_to
    event_response_applied_to revoke_applied_to
  ].freeze
  INCOMING_ONLY_KEYS = %w[waha_list_reply waha_poll_vote waha_event_response].freeze

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
