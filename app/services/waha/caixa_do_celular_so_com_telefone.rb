# #2211 — a caixa API ligada ao WAHA é o WhatsApp pelo celular: contato sem telefone não recebe por ela, como já não
# recebe pelo WhatsApp oficial nem pelo Twilio WhatsApp. Entra no Contacts::ContactableInboxesService por prepend (ver
# config/initializers/waha_caixa_do_celular_so_com_telefone.rb); as outras caixas API seguem como estão.
module Waha::CaixaDoCelularSoComTelefone
  private

  def api_contactable_inbox(inbox)
    return if inbox.channel.try(:waha_provider?) && @contact.phone_number.blank?

    super
  end
end
