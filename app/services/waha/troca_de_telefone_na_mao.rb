# #2711 (decisão do Rodrigo, 12/11: "Número novo, troca manual") — prepend em Api::V1::Accounts::ContactsController.
#
# Na caixa WAHA a mensagem sai pelo chat id guardado no contato (Waha::ContactChatId), não pelo telefone; a WAHA só
# pergunta pelo telefone quando o chat id não existe. Então, quando uma pessoa troca o telefone do contato no painel ou
# pela API de contatos (PATCH contacts/:id), o chat id, o jid e o lid saem no mesmo save, e a próxima mensagem pela
# caixa WAHA vai ao número novo. A próxima mensagem recebida grava o chat id de novo (`store!`).
#
# Só a troca: o contato tinha telefone e passa a ter outro. Pôr o primeiro telefone ou apagar o telefone não mexe no
# chat id. Só na conta com caixa WAHA. Importação, junção de contatos, sincronização da WAHA (API pública da caixa) e
# automação não passam por aqui.
module Waha::TrocaDeTelefoneNaMao
  private

  def contact_update_params
    attributes = super
    return attributes unless troca_de_telefone?(attributes[:phone_number])

    attributes.merge(custom_attributes: Waha::ContactChatId.without(contact_custom_attributes))
  end

  def troca_de_telefone?(novo)
    anterior = @contact.phone_number
    anterior.present? && novo.present? && novo != anterior && conta_com_waha?
  end

  def conta_com_waha?
    Channel::Api.joins(:inbox).where(account_id: Current.account.id)
                .exists?(["channel_api.additional_attributes ->> 'provider' = ?", 'waha'])
  end
end
