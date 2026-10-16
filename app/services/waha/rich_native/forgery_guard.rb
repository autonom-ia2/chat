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
# A mesma limpeza roda no modelo (Waha::RichNative::ContractGuard), para os caminhos que não passam por aqui (criação de
# conversa com mensagem); esta, no controller, segue como primeira barreira.
# INCONDICIONAL: vale com ou sem a flag `whatsapp_rich_native` (uma chave forjada ficaria guardada e valeria quando a
# flag fosse ligada). Entra como before_action, sem sobrescrever `create` (o Guia lê o formato da ação no método original).
module Waha::RichNative::ForgeryGuard
  ALWAYS_DROPPED = ['waha_native', 'waha_text', 'waha_media_as_media', RichMessages::SENT_AS_KEY].freeze
  INCOMING_ONLY_KEYS = Waha::RichNative::ContractGuard::INCOMING_ONLY_KEYS

  def self.prepended(controller)
    controller.before_action :drop_waha_contract_keys, only: :create
  end

  private

  def drop_waha_contract_keys
    raw = params[:content_attributes]
    attributes = raw.is_a?(String) ? parse_contract_attributes(raw) : raw
    return unless attributes.respond_to?(:key?)

    dropped = dropped_contract_keys.select { |key| attributes.key?(key) }
    return if dropped.empty?

    cleaned = attributes.except(*dropped)
    params[:content_attributes] = raw.is_a?(String) ? cleaned.to_json : cleaned
  end

  # As chaves gravadas pelo chat2you saem conforme a caixa da conversa (Waha::RichNative::ContractGuard.stored_keys_for):
  # as internas em qualquer uma, as de nome genérico só na WAHA comum e na do WhatsApp.
  def dropped_contract_keys
    keys = ALWAYS_DROPPED + Waha::RichNative::ContractGuard.stored_keys_for(@conversation&.inbox)
    params[:message_type].to_s == 'incoming' ? keys : keys + INCOMING_ONLY_KEYS
  end

  def parse_contract_attributes(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end
end
