# Um card "tem assunto" quando alguém (pessoa ou IA) deu nome ao pedido. O card criado sozinho pela caixa nasce com o
# nome do contato, o telefone ou "Conversa #N" (Crm::Cards::Creator#derived_title): esse ainda não tem assunto.
# Comparação exata de texto com o que a plataforma pôs, não interpretação do que o cliente escreveu.
module Crm::Subjects::Naming
  def self.named?(card)
    return true if card.metadata.to_h['subject'].present?

    title = card.title.to_s.strip
    title.present? && provisional_titles(card).none? { |provisional| provisional.casecmp?(title) }
  end

  def self.provisional_titles(card)
    contact = card.contact
    titles = [contact&.name, contact&.phone_number, contact&.email].map { |value| value.to_s.strip }
    titles << "Conversa ##{card.primary_conversation.display_id}" if card.primary_conversation
    titles.compact_blank
  end

  def self.metadata(card, source)
    (card.metadata || {}).merge('subject' => { 'source' => source, 'named_at' => Time.current.iso8601 })
  end
end
