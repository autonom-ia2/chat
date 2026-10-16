# Reações gravadas na mensagem reagida (chat#1709, fase 3): `content_attributes.reactions`, uma lista de
#   { "emoji" => "👍", "by" => "contact" | "business", "user_id" => 7 (quem reagiu pelo painel), "at" => ISO 8601 }
# No WhatsApp cada número tem UMA reação por mensagem. O número da empresa é um só: atendentes, IA e o celular da
# empresa são o mesmo autor ('business'). Por isso há no máximo duas reações por mensagem, a do contato e a da empresa:
# a nova de qualquer atendente (ou do celular) troca a anterior da empresa, e emoji vazio remove a da empresa, igual ao
# que o cliente vê. `user_id` só diz quem reagiu pelo painel (o celular não tem). Grava sob trava e sem as validações
# do modelo (a de rajada recusaria numa conversa movimentada); o `message_updated` leva a mudança à tela.
module Waha::RichNative::Reactions
  KEY = 'reactions'.freeze
  CONTACT = { 'by' => 'contact' }.freeze
  BUSINESS = 'business'.freeze
  # O WhatsApp reage com um emoji só (um grafema, que pode juntar vários códigos: bandeira, tom de pele).
  MAX_GRAPHEMES = 1

  module_function

  def valid_emoji?(emoji)
    emoji.is_a?(String) && emoji.grapheme_clusters.size <= MAX_GRAPHEMES && emoji.bytesize <= 64
  end

  # A empresa reagindo; `user_id` quando foi pelo painel.
  def business_author(user_id = nil)
    { 'by' => BUSINESS, 'user_id' => user_id }.compact
  end

  # author: CONTACT ou business_author.
  def apply!(message, emoji:, author:)
    message.with_lock do
      reactions = Array(message.content_attributes.to_h[KEY]).reject { |reaction| same_author?(reaction, author) }
      reactions << author.merge('emoji' => emoji, 'at' => Time.current.iso8601) if emoji.present?
      message.content_attributes = message.content_attributes.to_h.merge(KEY => reactions)
      message.save!(validate: false)
    end
  end

  def same_author?(reaction, author)
    reaction.is_a?(Hash) && reaction['by'] == author['by']
  end
end
