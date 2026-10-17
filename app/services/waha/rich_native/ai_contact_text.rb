# O texto que a IA lê de um cartão de contato (chat#1709, decisão do Rodrigo de 17/10/2026: a IA VÊ o telefone, venha o
# cartão da equipe ou do cliente). Com a flag `whatsapp_rich_native`:
# - do cliente (caixa WAHA comum): `shared_contacts` [{ full_name, phones, wa_id }] (Waha::RichNative::Inbound::Contacts);
# - da equipe: o `rich_message` de contato (chat#1473) { name, phone, wa_id }, que vai com `content` vazio.
# No formato do #1753, um contato por linha: "Contato: nome — tel1, tel2"; sem nome, "Contato: tel1"; sem nome nem
# telefone, "Contato (sem nome)". O texto de reserva da Cloud para contato sem telefone (NO_PHONE, de
# Whatsapp::IncomingContactMessageHandler) nunca entra. Lido pelo Waha::RichNative::ResponderLocation, junto do
# `content`. Sem a flag ou sem contato: nil, e nada muda.
module Waha::RichNative::AiContactText
  KEY = 'shared_contacts'.freeze
  LABEL = 'Contato'.freeze
  UNNAMED = 'Contato (sem nome)'.freeze
  SEPARATOR = ' — '.freeze
  NO_PHONE = 'Phone number is not available'.freeze

  module_function

  def for(message)
    return if message.nil? || !Waha::RichNative.enabled?(message.account)

    lines = contacts_of(message).map { |name, phones| line_for(name, phones) }
    lines.join("\n").presence
  end

  # [[nome, [telefones]]] do cliente e da equipe.
  def contacts_of(message)
    attributes = message.content_attributes.to_h
    shared = Array(attributes[KEY]).select { |contact| contact.is_a?(Hash) }.map do |contact|
      [contact['full_name'], Array(contact['phones'])]
    end
    rich = attributes[RichMessages::KEY]
    shared << [rich['name'], [rich['phone']]] if rich.is_a?(Hash) && rich['type'] == 'contact'
    shared
  end

  def line_for(name, phones)
    phones = phones.filter_map { |phone| Waha::RichNative::AiLocationText.line(phone) }.compact_blank - [NO_PHONE]
    label = Waha::RichNative::AiLocationText.line(name).presence
    return "#{LABEL}: #{[label, phones.join(', ').presence].compact.join(SEPARATOR)}" if label || phones.any?

    UNNAMED
  end
end
