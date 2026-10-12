# Leitor e escritor únicos do chat id WAHA do contato (#1324).
#
# O app Chatwoot da WAHA cria o contato pela API pública da caixa sem `source_id` (o Chatwoot gera um UUID para o
# `ContactInbox`) e guarda o chat id nos atributos do contato: `waha_whatsapp_chat_id` (o endereço que a WAHA usa para
# mandar), `waha_whatsapp_jid` (`@c.us`) e `waha_whatsapp_lid` (`@lid`). Quem precisa do chat id lê por aqui; o
# `source_id` do `ContactInbox` entra como reserva para provedores que guardam o JID nele.
#
# Leitura (só valores presentes, na ordem pedida, sem normalizar):
# - `candidates(contact, contact_inbox:)`: chat_id → jid → source_id. O lid fica fora: `@lid` é só 1:1.
# - `primary(contact, contact_inbox:)`: o primeiro dos candidatos.
# - `values(contact, *keys, contact_inbox:)`: só as fontes pedidas, entre `:chat_id`, `:jid` e `:source_id`.
#
# Escrita: `store!(contact, chat_id)`, como a WAHA faz a cada mensagem recebida.
class Waha::ContactChatId
  CHAT_ID = 'waha_whatsapp_chat_id'.freeze
  JID = 'waha_whatsapp_jid'.freeze
  LID = 'waha_whatsapp_lid'.freeze
  LID_SUFFIX = '@lid'.freeze
  CANDIDATE_SOURCES = %i[chat_id jid source_id].freeze

  class << self
    def candidates(contact, contact_inbox: nil)
      values(contact, *CANDIDATE_SOURCES, contact_inbox: contact_inbox)
    end

    def primary(contact, contact_inbox: nil)
      candidates(contact, contact_inbox: contact_inbox).first
    end

    def values(contact, *sources, contact_inbox: nil)
      attributes = contact&.custom_attributes.to_h
      sources.map { |source| read(source, attributes, contact_inbox) }.select(&:present?)
    end

    # O chat id confirmado passa a ser o `waha_whatsapp_chat_id` e vai também na chave do tipo dele (jid ou lid); a outra
    # chave e os demais atributos ficam. Contato já salvo é gravado; contato novo só recebe os atributos, para quem chama
    # gravar junto.
    def store!(contact, chat_id)
      current = contact.custom_attributes.to_h
      merged = current.merge(CHAT_ID => chat_id, (chat_id.end_with?(LID_SUFFIX) ? LID : JID) => chat_id)
      return if merged == current

      contact.new_record? ? contact.assign_attributes(custom_attributes: merged) : contact.update!(custom_attributes: merged)
    end

    private

    def read(source, attributes, contact_inbox)
      case source
      when :chat_id then attributes[CHAT_ID]
      when :jid then attributes[JID]
      when :source_id then contact_inbox&.source_id
      else raise ArgumentError, "unknown WAHA chat id source: #{source.inspect}"
      end
    end
  end
end
