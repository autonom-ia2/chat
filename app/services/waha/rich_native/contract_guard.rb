# Callback `before_create` de Message (chat#1709, fases 2 e 3), o PRIMEIRO dos callbacks do contrato com o conector do
# WAHA. Vale em qualquer caminho de criação (API de mensagens, criação de conversa com mensagem, job, console), com ou
# sem a flag `whatsapp_rich_native`, mas só tira chaves que NENHUM outro código grava (nomes `waha_*`, `c2y_*` e
# `*_applied_to`, que só o chat2you e o conector usam):
# - REQUEST_KEYS (pedido ao conector, só no payload do webhook da caixa): `waha_native` (Waha::RichNative::InboxWebhook),
#   `waha_text` e `waha_media_as_media` (Waha::RichNative::OutgoingHints). Guardadas, iriam ao conector e o motor mandaria
#   o que quem criou quisesse. Saem SEMPRE.
# - INTERNAL_KEYS (marca interna, como `c2y_hidden`, que esconderia do painel uma mensagem que foi ao cliente): saem
#   SEMPRE na entrada. Quem as grava (Waha::RichNative::Inbound e os módulos de gravação) roda DEPOIS deste callback, ou
#   marca a mensagem como escrita interna (Waha::RichNative::InternalWrite, montada antes do `save!`).
# - INCOMING_ONLY_KEYS (`waha_list_reply`, `waha_poll_vote`, `waha_event_response`): a escolha, o voto e a resposta ao
#   evento do cliente só existem em mensagem RECEBIDA, que é como o conector as cria. Em qualquer outra, saem.
# As SCOPED_KEYS (nomes genéricos do formato da tela do Frontend geral, #1702: `reactions`, `forwarded`,
# `unsupported_kind`, `quoted_message`…) NÃO saem aqui: o recebimento da Cloud e o encaminhamento do #1702b as gravam
# na criação, por dentro. A forja delas só é barrada na API pública (Waha::RichNative::ForgeryGuard, criação de
# mensagem, e Waha::RichNative::ConversationForgeryGuard, criação de conversa com mensagem), na caixa WAHA comum e na
# do WhatsApp.
class Waha::RichNative::ContractGuard
  REQUEST_KEYS = %w[waha_native waha_text waha_media_as_media].freeze
  INTERNAL_KEYS = %w[
    c2y_hidden waha_unknown_type waha_call_summary waha_ephemeral reaction_applied_to edit_applied_to
    poll_vote_applied_to event_response_applied_to revoke_applied_to c2y_ai_turn
  ].freeze
  SCOPED_KEYS = %w[
    reactions edit_history edited_at selected_options poll_votes event_responses deleted_by_contact_at unsupported_kind
    forwarded frequently_forwarded played_at quoted_message media_unavailable shared_contacts
    view_once_unavailable view_once_id view_once_resolved_by
  ].freeze
  STORED_KEYS = (INTERNAL_KEYS + SCOPED_KEYS).freeze
  # As caixas onde o chat2you grava as SCOPED_KEYS: a WAHA comum (Channel::Api com provider 'waha') e a do WhatsApp
  # (o plano B do Híbrido grava voto, reação e citação nela).
  SCOPED_CHANNEL = 'Channel::Whatsapp'.freeze
  INCOMING_ONLY_KEYS = %w[waha_list_reply waha_poll_vote waha_event_response].freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    dropped = dropped_keys(message).select { |key| attributes.key?(key) }
    message.content_attributes = attributes.except(*dropped) if dropped.any?
  end

  def self.dropped_keys(message)
    keys = REQUEST_KEYS
    keys += INTERNAL_KEYS unless Waha::RichNative::InternalWrite.internal?(message)
    keys += INCOMING_ONLY_KEYS unless message.incoming?
    keys
  end

  # As chaves gravadas pelo chat2you que a API pública não aceita numa mensagem desta caixa.
  def self.stored_keys_for(inbox)
    scoped_inbox?(inbox) ? STORED_KEYS : INTERNAL_KEYS
  end

  def self.scoped_inbox?(inbox)
    return false if inbox.nil?
    return true if inbox.channel_type == SCOPED_CHANNEL

    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end
end
