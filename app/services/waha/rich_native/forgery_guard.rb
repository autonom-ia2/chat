# Prepend em Api::V1::Accounts::Conversations::MessagesController (chat#1709, fase 2): as chaves do contrato com o
# conector do WAHA não podem ser forjadas por quem cria mensagem pela API.
# - `waha_native` (o pedido ao motor) só existe no webhook da caixa, montado a partir do `rich_message`: sai SEMPRE.
#   Guardado na mensagem, iria ao conector e o motor mandaria o que quem criou quisesse.
# - `rich_message_sent_as` (a marca) é decidida na criação (Waha::RichNative::ApiInboxDecision): sai SEMPRE.
# - `waha_list_reply` (a escolha do cliente) só vale em mensagem RECEBIDA, que é como o conector a cria; em qualquer
#   outra, sai. Na recebida, Waha::RichNative::ListReply a confere antes de ligar a resposta (lista nativa da mesma
#   conversa e caixa).
# Entra como before_action, sem sobrescrever `create` (o Guia lê o formato da ação no método original).
module Waha::RichNative::ForgeryGuard
  ALWAYS_DROPPED = ['waha_native', RichMessages::SENT_AS_KEY].freeze
  INCOMING_ONLY = 'waha_list_reply'.freeze

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

  def dropped_contract_keys
    params[:message_type].to_s == 'incoming' ? ALWAYS_DROPPED : ALWAYS_DROPPED + [INCOMING_ONLY]
  end

  def parse_contract_attributes(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end
end
