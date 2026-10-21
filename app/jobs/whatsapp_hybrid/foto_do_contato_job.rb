# Busca a foto de perfil do contato pela sessão WAHA da caixa híbrida (#1934). Ver WhatsappHybrid::FotoDoContato.
class WhatsappHybrid::FotoDoContatoJob < ApplicationJob
  queue_as :low

  def perform(contact_id, inbox_id)
    contact = Contact.find_by(id: contact_id)
    connection = WhatsappHybrid::Connection.find_by(inbox_id: inbox_id)
    return unless contact && connection && contact.account_id == connection.account_id

    WhatsappHybrid::FotoDoContato.new(contact: contact, connection: connection).perform
  end
end
