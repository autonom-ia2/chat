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
#   Duas faixas (revisão da rodada 2):
#   - INTERNAL_KEYS (marca interna e nomes `waha_*`/`*_applied_to`, que só o chat2you usa): saem em QUALQUER caixa;
#   - SCOPED_KEYS (nomes genéricos: `reactions`, `forwarded`, `quoted_message`…): saem só onde o chat2you as grava, a
#     caixa WAHA comum e a caixa do WhatsApp (Híbrido). Noutra caixa (Channel::Api de outro provedor, n8n, importador)
#     a chave que alguém mandar fica, como na main.
# - INCOMING_ONLY_KEYS (`waha_list_reply`, `waha_poll_vote`, `waha_event_response`): a escolha, o voto e a resposta ao
#   evento do cliente só existem em mensagem RECEBIDA, que é como o conector as cria. Em qualquer outra, saem.
class Waha::RichNative::ContractGuard
  REQUEST_KEYS = %w[waha_native waha_text waha_media_as_media].freeze
  INTERNAL_KEYS = %w[
    c2y_hidden waha_unknown_type waha_call_summary waha_ephemeral reaction_applied_to edit_applied_to
    poll_vote_applied_to event_response_applied_to revoke_applied_to
  ].freeze
  SCOPED_KEYS = %w[
    reactions edit_history edited_at selected_options poll_votes event_responses deleted_by_contact_at unsupported_kind
    forwarded frequently_forwarded played_at quoted_message media_unavailable shared_contacts
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
    keys += stored_keys_for(message.inbox) unless Waha::RichNative::InternalWrite.internal?(message)
    keys += INCOMING_ONLY_KEYS unless message.incoming?
    keys
  end

  # As chaves gravadas pelo chat2you que saem numa mensagem desta caixa.
  def self.stored_keys_for(inbox)
    scoped_inbox?(inbox) ? STORED_KEYS : INTERNAL_KEYS
  end

  def self.scoped_inbox?(inbox)
    return false if inbox.nil?
    return true if inbox.channel_type == SCOPED_CHANNEL

    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) ? true : false
  end
end
