# #2211 — a caixa API ligada ao WAHA é o WhatsApp pelo celular: só oferece começar conversa com quem tem um endereço no
# WhatsApp. Contato sem telefone fica sem ela, como já fica sem o WhatsApp oficial e o Twilio WhatsApp — a não ser que
# a WAHA já saiba o chat dele (contato que chegou só com LID): a WAHA manda para o `waha_whatsapp_chat_id` (ou o jid),
# que Waha::ContactChatId lê. O `source_id` do contact_inbox vale quando é um chat id do WhatsApp; o app da WAHA cria o
# vínculo com um UUID, que não é endereço. Entra no Contacts::ContactableInboxesService por prepend (ver
# config/initializers/waha_caixa_do_celular_so_com_telefone.rb); as outras caixas API seguem como estão.
module Waha::CaixaDoCelularSoComTelefone
  SUFIXOS_DE_CHAT = %w[@c.us @s.whatsapp.net @lid].freeze

  private

  def api_contactable_inbox(inbox)
    return if inbox.channel.try(:waha_provider?) && !endereco_no_whatsapp?(inbox)

    super
  end

  def endereco_no_whatsapp?(inbox)
    return true if @contact.phone_number.present?
    return true if Waha::ContactChatId.values(@contact, :chat_id, :jid).any?

    vinculo = inbox.contact_inboxes.where(contact: @contact).last
    SUFIXOS_DE_CHAT.any? { |sufixo| vinculo&.source_id.to_s.end_with?(sufixo) }
  end
end
