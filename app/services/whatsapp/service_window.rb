# Janela de atendimento do WhatsApp por contato e caixa (#1335, épico #1320). A Meta abre a janela quando a pessoa manda
# mensagem e ela dura 24 horas a partir da última; dentro dela vale mensagem sem modelo. Aqui a janela é a do CONTATO
# na CAIXA (não a da conversa, como `Conversations::MessageWindowService`): campanha fala com pessoas, e a mesma pessoa
# pode ter mais de uma conversa na caixa. A hora vem da última mensagem recebida dela (messages.created_at).
#
#   window = Whatsapp::ServiceWindow.new(inbox: inbox)
#   window.open_contact_ids(ids)   # => Set dos contatos dentro da janela (consulta em lotes)
#   window.open?(contact)          # => conferência de uma pessoa, na hora do envio
class Whatsapp::ServiceWindow
  DURATION = 24.hours
  CLOSING_SOON = 2.hours
  BATCH_SIZE = 1000

  def initialize(inbox:, now: Time.current)
    @inbox = inbox
    @now = now
  end

  def open_contact_ids(contact_ids)
    last_incoming_by_contact(contact_ids).keys.to_set
  end

  # Quantos, dos que estão dentro, saem da janela nas próximas 2 horas.
  def closing_soon_count(contact_ids)
    limit = @now - DURATION + CLOSING_SOON
    last_incoming_by_contact(contact_ids).values.count { |at| at < limit }
  end

  def open?(contact)
    last_incoming_by_contact([contact.id]).key?(contact.id)
  end

  private

  # { contact_id => hora da última mensagem recebida dentro das 24 h }
  def last_incoming_by_contact(contact_ids)
    Array(contact_ids).uniq.each_slice(BATCH_SIZE).with_object({}) do |ids, result|
      result.merge!(incoming_scope.where(sender_id: ids).group(:sender_id).maximum(:created_at))
    end
  end

  def incoming_scope
    Message.where(account_id: @inbox.account_id, inbox_id: @inbox.id, message_type: :incoming, sender_type: 'Contact',
                  created_at: (@now - DURATION)..@now).reorder(nil)
  end
end
