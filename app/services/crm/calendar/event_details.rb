# #1568 — o que o calendário "Meu dia" mostra em cada evento sem uma chamada a mais por item: o nome e o telefone do
# cliente e o número da conversa (o display_id, que é o da rota). Em lote: uma consulta de contatos e uma de conversas
# para a lista inteira. A conversa só ganha número quando o evento já trouxe o id dela, ou seja, quando quem pediu pode vê-la.
class Crm::Calendar::EventDetails
  def initialize(account:, events:)
    @account = account
    @events = events
  end

  def perform
    @events.map do |event|
      contact = contacts[event[:contact_id]]
      event.merge(
        contact_name: contact&.dig(:name),
        contact_phone: contact&.dig(:phone),
        conversation_display_id: display_ids[event[:conversation_id]]
      )
    end
  end

  private

  def ids(key)
    @events.filter_map { |event| event[key] }.uniq
  end

  def contacts
    @contacts ||= @account.contacts.where(id: ids(:contact_id)).pluck(:id, :name, :phone_number)
                          .to_h { |id, name, phone| [id, { name: name, phone: phone.presence }] }
  end

  def display_ids
    @display_ids ||= @account.conversations.where(id: ids(:conversation_id)).pluck(:id, :display_id).to_h
  end
end
