# Reações gravadas na mensagem reagida (chat#1709, fase 3): `content_attributes.reactions`, uma lista de
#   { "emoji" => "👍", "by" => "contact" | "phone" | "agent", "user_id" => 7 (só agent), "at" => ISO 8601 }
# Cada autor tem uma reação por mensagem: a nova troca a anterior do mesmo autor (o contato, o celular da empresa ou
# cada atendente pelo user_id), e emoji vazio a remove, como no WhatsApp. Grava sob trava e sem as validações do
# modelo (a de rajada recusaria numa conversa movimentada); o `message_updated` leva a mudança à tela.
module Waha::RichNative::Reactions
  KEY = 'reactions'.freeze
  # O WhatsApp reage com um emoji só (um grafema, que pode juntar vários códigos: bandeira, tom de pele).
  MAX_GRAPHEMES = 1

  module_function

  def valid_emoji?(emoji)
    emoji.is_a?(String) && emoji.grapheme_clusters.size <= MAX_GRAPHEMES && emoji.bytesize <= 64
  end

  # author: { 'by' => 'contact' } ou { 'by' => 'agent', 'user_id' => 7 }.
  def apply!(message, emoji:, author:)
    message.with_lock do
      reactions = Array(message.content_attributes.to_h[KEY]).reject { |reaction| same_author?(reaction, author) }
      reactions << author.merge('emoji' => emoji, 'at' => Time.current.iso8601) if emoji.present?
      message.content_attributes = message.content_attributes.to_h.merge(KEY => reactions)
      message.save!(validate: false)
    end
  end

  def same_author?(reaction, author)
    reaction.is_a?(Hash) && reaction['by'] == author['by'] && reaction['user_id'] == author['user_id']
  end
end
