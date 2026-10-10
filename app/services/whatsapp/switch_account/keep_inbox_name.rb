# chat#1217 — Reconectar ou trocar a conta do WhatsApp não muda o nome da caixa.
# Prepend em Whatsapp::ReauthorizationService: o serviço do Chatwoot renomeia a caixa para o nome
# verificado na Meta. No fork o nome da caixa é escolhido pela operação e usado no dia a dia
# (decisão do Rodrigo, 10/10/2026), então o nome vindo da Meta não é repassado.
module Whatsapp::SwitchAccount::KeepInboxName
  private

  def update_channel_config(channel, access_token, phone_info)
    super(channel, access_token, phone_info.except(:business_name, :verified_name))
  end
end
