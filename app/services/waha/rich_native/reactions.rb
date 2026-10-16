# Reações gravadas na mensagem reagida (chat#1709; formato da tela do Frontend geral, #1702):
#   content_attributes.reactions = [{ "emoji" => "👍", "sender_type" => "Contact" | "User", "sender_id" => 12 | nil,
#                                     "at" => ISO 8601 }]
# No WhatsApp cada número tem UMA reação por mensagem.
# - Contact: o contato da conversa (`sender_id` = contact_id); uma por (sender_type, sender_id).
# - User: o número da EMPRESA. Atendentes, IA e o celular da empresa são o mesmo autor, então há uma só reação 'User':
#   a nova de qualquer atendente (ou do celular) troca a anterior, e emoji vazio remove, igual ao que o cliente vê.
#   `sender_id` = o atendente que reagiu pelo painel, ou nil quando veio do celular da empresa.
# Emoji vazio remove a reação do autor; lista vazia tira a chave. Grava sob trava e sem as validações do modelo (a de
# rajada recusaria numa conversa movimentada); o `message_updated` (after_update_commit) leva a mudança à tela.
module Waha::RichNative::Reactions
  KEY = 'reactions'.freeze
  CONTACT_TYPE = 'Contact'.freeze
  USER_TYPE = 'User'.freeze
  # O WhatsApp reage com um emoji só (um grafema, que pode juntar vários códigos: bandeira, tom de pele).
  MAX_GRAPHEMES = 1

  module_function

  def valid_emoji?(emoji)
    emoji.is_a?(String) && emoji.grapheme_clusters.size <= MAX_GRAPHEMES && emoji.bytesize <= 64
  end

  # O contato reagindo.
  def contact_author(contact_id)
    { 'sender_type' => CONTACT_TYPE, 'sender_id' => contact_id }
  end

  # A empresa reagindo; `user_id` quando foi pelo painel (nil: celular da empresa).
  def business_author(user_id = nil)
    { 'sender_type' => USER_TYPE, 'sender_id' => user_id }
  end

  # author: contact_author ou business_author. timestamp: a hora da reação no WhatsApp, quando o conector a mandar
  # (Waha::RichNative::EventTime); a reação guardada do mesmo autor só muda por uma igual ou mais nova. Sem ela (o
  # painel, e o conector c2y-rich-3, que ainda não manda a hora da reação), vale a ordem de chegada.
  def apply!(message, emoji:, author:, timestamp: nil)
    at = Waha::RichNative::EventTime.iso8601(timestamp)
    message.with_lock do
      current = Array(message.content_attributes.to_h[KEY])
      next if stale?(current.find { |reaction| same_author?(reaction, author) }, at, timestamp)

      reactions = current.reject { |reaction| same_author?(reaction, author) }
      reactions << { 'emoji' => emoji }.merge(author).merge('at' => at) if emoji.present?
      attributes = message.content_attributes.to_h
      message.content_attributes = reactions.empty? ? attributes.except(KEY) : attributes.merge(KEY => reactions)
      message.save!(validate: false)
    end
  end

  # Só com a hora do WhatsApp: a reação guardada é mais nova que esta.
  def stale?(previous, at, timestamp)
    timestamp.present? && previous.present? && !Waha::RichNative::EventTime.replaces?(at, previous['at'])
  end

  def same_author?(reaction, author)
    return false unless reaction.is_a?(Hash) && reaction['sender_type'] == author['sender_type']

    author['sender_type'] == USER_TYPE || reaction['sender_id'] == author['sender_id']
  end
end
