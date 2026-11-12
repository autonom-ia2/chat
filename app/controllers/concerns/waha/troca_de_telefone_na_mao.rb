# #2711 — prepend em Api::V1::Accounts::ContactsController.
#
# Quando a pessoa muda o telefone do contato no painel ou pela API de contatos (PATCH contacts/:id), o chat id da WAHA
# sai no mesmo save, mesmo que o pedido o mande de volta, e a próxima mensagem pela caixa WAHA vai ao número novo. A
# regra de quando sai fica em Waha::TelefoneNovo. Pedido sem `phone_number` não mexe no chat id.
#
# Mora em app/controllers/concerns porque é código do controller: o gerador de formatos do Guia (#900) só lê os
# controllers, e fora daqui o override escondia o `permit` do Chatwoot (PATCH contacts/:id saía incompleto).
module Waha::TrocaDeTelefoneNaMao
  private

  def contact_update_params
    attributes = super
    return attributes unless attributes.key?(:phone_number)

    attributes.merge(custom_attributes: Waha::TelefoneNovo.custom_attributes(@contact, attributes[:phone_number], contact_custom_attributes))
  end
end
