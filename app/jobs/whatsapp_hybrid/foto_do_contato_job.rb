# Busca a foto de perfil do contato pela sessão WAHA da caixa híbrida (#1934). Ver WhatsappHybrid::FotoDoContato.
class WhatsappHybrid::FotoDoContatoJob < ApplicationJob
  queue_as :low

  # teto: só o backfill passa (WhatsappHybrid::FotoDoContatoBackfillJob::TETO_DO_BACKFILL); o ao vivo usa o do serviço.
  def perform(contact_id, inbox_id, teto = nil)
    contact = Contact.find_by(id: contact_id)
    connection = WhatsappHybrid::Connection.find_by(inbox_id: inbox_id)
    return unless contact && connection && contact.account_id == connection.account_id

    opcoes = teto ? { teto: teto } : {}
    WhatsappHybrid::FotoDoContato.new(contact: contact, connection: connection, **opcoes).perform
  end
end
