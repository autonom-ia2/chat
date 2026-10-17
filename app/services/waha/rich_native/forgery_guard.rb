# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1709, fase 2): as chaves do contrato com o
# conector do WAHA não podem ser forjadas por quem cria mensagem pela API.
# - `waha_native` (o pedido ao motor) só existe no webhook da caixa, montado a partir do `rich_message`: sai SEMPRE.
#   Guardado na mensagem, iria ao conector e o motor mandaria o que quem criou quisesse.
# - `rich_message_sent_as` (a marca) é decidida na criação (Waha::RichNative::ApiInboxDecision): sai SEMPRE.
# - `waha_list_reply` (a escolha do cliente) só vale em mensagem RECEBIDA, que é como o conector a cria; em qualquer
#   outra, sai. Na recebida, Waha::RichNative::ListReply só a converte em escolha se uma lista nativa nossa da mesma
#   conversa e caixa ofereceu essa opção; senão, a chave sai e a mensagem fica como texto comum.
# - Fase 3: `waha_text` e `waha_media_as_media` (pedidos ao conector, como o `waha_native`) e as chaves que o chat2you
#   GRAVA ao transformar o que o conector manda (Waha::RichNative::ContractGuard::STORED_KEYS: `c2y_hidden`,
#   `reactions`, `edit_history`, `poll_votes`, `deleted_by_contact_at` etc.): as internas (`c2y_hidden`, `waha_*`,
#   `*_applied_to`) saem SEMPRE; as de nome genérico, só na caixa WAHA comum e na do WhatsApp (revisão da rodada 2).
#   Forjada, `c2y_hidden` esconderia uma mensagem do painel.
# - `waha_poll_vote` (o voto do cliente) e `waha_event_response` (a resposta ao evento), como a escolha de lista, só em
#   mensagem RECEBIDA. As outras chaves do conector
#   (`waha_call`, `waha_unknown`, `waha_reaction`, `waha_edit`) também vêm em nota ou mensagem nossa (eventos do celular
#   da empresa) e ficam aqui: Waha::RichNative::Inbound só as aceita de quem é o conector (o dono do token da caixa) e
#   as tira de qualquer outro usuário, em qualquer caminho de criação.
# A criação de conversa com mensagem passa pela mesma limpeza (Waha::RichNative::ConversationForgeryGuard). No modelo
# (Waha::RichNative::ContractGuard) só saem as chaves que nenhum outro código grava: as de nome genérico são gravadas
# por dentro (recebimento da Cloud, encaminhamento do #1702b) e só a API pública as barra.
# INCONDICIONAL: vale com ou sem a flag `whatsapp_rich_native` (uma chave forjada ficaria guardada e valeria quando a
# flag fosse ligada). Entra como before_action, sem sobrescrever `create` (o Guia lê o formato da ação no método original).
module Waha::RichNative::ForgeryGuard
  ALWAYS_DROPPED = ['waha_native', 'waha_text', 'waha_media_as_media', RichMessages::SENT_AS_KEY].freeze
  INCOMING_ONLY_KEYS = Waha::RichNative::ContractGuard::INCOMING_ONLY_KEYS

  def self.prepended(controller)
    controller.before_action :drop_waha_contract_keys, only: :create
  end

  # O `content_attributes` cru do pedido (hash ou JSON em texto) sem as chaves do contrato; o mesmo valor quando não há o
  # que tirar. inbox: a caixa da conversa; incoming: a mensagem pedida é recebida.
  def self.clean(raw, inbox:, incoming:)
    attributes = raw.is_a?(String) ? parse(raw) : raw
    return raw unless attributes.respond_to?(:key?)

    dropped = dropped_keys(inbox, incoming).select { |key| attributes.key?(key) }
    return raw if dropped.empty?

    cleaned = attributes.except(*dropped)
    raw.is_a?(String) ? cleaned.to_json : cleaned
  end

  # As chaves gravadas pelo chat2you saem conforme a caixa da conversa (Waha::RichNative::ContractGuard.stored_keys_for):
  # as internas em qualquer uma, as de nome genérico só na WAHA comum e na do WhatsApp.
  def self.dropped_keys(inbox, incoming)
    keys = ALWAYS_DROPPED + Waha::RichNative::ContractGuard.stored_keys_for(inbox)
    incoming ? keys : keys + INCOMING_ONLY_KEYS
  end

  def self.parse(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  private

  def drop_waha_contract_keys
    return unless params.key?(:content_attributes)

    incoming = params[:message_type].to_s == 'incoming'
    params[:content_attributes] = Waha::RichNative::ForgeryGuard.clean(params[:content_attributes], inbox: @conversation&.inbox, incoming: incoming)
  end
end
