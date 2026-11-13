# #2711 — o telefone do contato muda e a caixa WAHA passa a mandar ao número novo.
#
# Na caixa WAHA a mensagem sai pelo chat id guardado no contato (Waha::ContactChatId), não pelo telefone; a WAHA só
# pergunta pelo telefone quando o chat id não existe. Então, quando o telefone muda por decisão de alguém (a pessoa no
# painel ou na API de contatos, Waha::TrocaDeTelefoneNaMao; a regra de automação que grava o telefone,
# Autonomia::Decisores::Aplicador), o chat id, o jid e o lid saem no mesmo save. A próxima mensagem recebida grava o
# chat id de novo (`store!`).
#
# Saem quando:
# - o contato tinha telefone e passa a ter outro, ou fica sem (apagar e depois pôr outro número não guarda o antigo);
# - o contato não tinha telefone, ganha um, e o endereço guardado é um `@c.us` de outro número. O `@lid` é da pessoa,
#   não do número, e fica.
# Só na conta com caixa WAHA. Importação, junção de contatos e sincronização da WAHA (API pública da caixa) não passam
# por aqui.
class Waha::TelefoneNovo
  C_US_SUFFIX = '@c.us'.freeze

  # Os atributos que o contato grava junto com o telefone `phone`.
  def self.custom_attributes(contact, phone, custom_attributes = contact.custom_attributes.to_h)
    new(contact, phone).stale? ? Waha::ContactChatId.without(custom_attributes) : custom_attributes
  end

  def initialize(contact, phone)
    @contact = contact
    @before = contact.phone_number.presence
    @after = phone.presence
  end

  def stale?
    return false if @after == @before

    (@before.present? || other_number?) && waha_account?
  end

  private

  def other_number?
    Waha::ContactChatId.values(@contact, :chat_id, :jid).any? do |id|
      id.end_with?(C_US_SUFFIX) && id.delete_suffix(C_US_SUFFIX) != @after.delete('^0-9')
    end
  end

  def waha_account?
    Channel::Api.joins(:inbox).where(account_id: @contact.account_id)
                .exists?(["channel_api.additional_attributes ->> 'provider' = ?", 'waha'])
  end
end
