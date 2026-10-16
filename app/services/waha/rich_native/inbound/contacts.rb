# `waha_contacts` (chat#1709, rodada 2): contato(s) compartilhado(s), [{ full_name, phones: [texto], wa_id }], na mesma
# ordem dos .vcf que o conector anexa. Vira o cartão de contato do painel (bubbles/Contact.vue, com "Adicionar
# contato"), como a Cloud (attach_contact): os .vcf saem e entra um anexo `contact` por telefone (fallback_title =
# telefone, meta { firstName, lastName }). O cartão aparece com exatamente 1 telefone no total; com mais, fica a bolha
# de texto do conector, sem os .vcf, igual à Cloud. Os dados do vCard ficam em `shared_contacts`; o texto continua
# (a IA e a busca o leem).
module Waha::RichNative::Inbound::Contacts
  KEY = 'shared_contacts'.freeze
  VCARD_EXTENSION = '.vcf'.freeze
  LID_SUFFIX = '@lid'.freeze

  module_function

  def apply(message, data)
    contacts = valid_contacts(data)
    return if !message.incoming? || contacts.empty?

    message.attachments.select { |attachment| vcard?(attachment) }.each { |attachment| message.attachments.delete(attachment) }
    contacts.each { |contact| attach!(message, contact) }
    message.content_attributes = message.content_attributes.to_h.merge(KEY => contacts)
  end

  def valid_contacts(data)
    Array(data).select { |contact| contact.is_a?(Hash) }.map do |contact|
      { 'full_name' => contact['full_name'].to_s, 'phones' => Array(contact['phones']).map(&:to_s).compact_blank,
        'wa_id' => digits_only(contact['wa_id']) }
    end
  end

  # Só os dígitos do número: sem `@c.us` e sem o sufixo `:<aparelho>` (ex.: "5511999998888:12@c.us"). nil sem nenhum
  # dígito e nil para `@lid`: o LID é um identificador interno do WhatsApp, não telefone. Por métodos de texto, sem regex.
  def digits_only(wa_id)
    return if wa_id.to_s.end_with?(LID_SUFFIX)

    user = wa_id.to_s.split('@').first.to_s.split(':').first.to_s
    digits = user.delete('^0-9')
    digits.presence
  end

  def attach!(message, contact)
    first_name, last_name = contact['full_name'].split(' ', 2)
    meta = { 'firstName' => first_name, 'lastName' => last_name }.compact
    contact['phones'].each do |phone|
      message.attachments.new(account_id: message.account_id, file_type: :contact, fallback_title: phone, meta: meta)
    end
  end

  def vcard?(attachment)
    attachment.attachment_changes['file']&.blob&.filename.to_s.downcase.end_with?(VCARD_EXTENSION)
  end
end
