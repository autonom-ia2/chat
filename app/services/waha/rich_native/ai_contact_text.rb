# O texto que a IA lê de um cartão de contato (chat#1709, decisão do Rodrigo de 17/10/2026: a IA VÊ o telefone, venha o
# cartão da equipe ou do cliente). Com a flag `whatsapp_rich_native`:
# - do cliente (caixa WAHA comum): `shared_contacts` [{ full_name, phones, wa_id }] (Waha::RichNative::Inbound::Contacts);
# - da equipe: o `rich_message` de contato (chat#1473) { name, phone, wa_id }, que vai com `content` vazio.
# Um contato por linha: "Contato: nome — telefone[, telefone]" ("Contato (sem nome)" quando falta o nome). Lido pelo
# Waha::RichNative::ResponderLocation, junto do `content`. Sem a flag ou sem contato: nil, e nada muda.
module Waha::RichNative::AiContactText
  KEY = 'shared_contacts'.freeze
  LABEL = 'Contato'.freeze
  UNNAMED = 'Contato (sem nome)'.freeze
  SEPARATOR = ' — '.freeze

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
    phones = phones.filter_map { |phone| Waha::RichNative::AiLocationText.line(phone) }.compact_blank
    label = Waha::RichNative::AiLocationText.line(name).presence
    head = label ? "#{LABEL}: #{label}" : UNNAMED
    phones.empty? ? head : "#{head}#{SEPARATOR}#{phones.join(', ')}"
  end
end
