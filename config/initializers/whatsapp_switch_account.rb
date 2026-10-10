# frozen_string_literal: true

# chat#1217 — Trocar a caixa de WhatsApp de conta (outra WABA / outro portfólio da Meta) sem perder a caixa.
# Tudo no fork por prepend; o serviço e o controller do Chatwoot ficam intactos.
Rails.application.config.to_prepare do
  unless Whatsapp::EmbeddedSignupService <= Whatsapp::SwitchAccount::SameNumberGuard
    Whatsapp::EmbeddedSignupService.prepend(Whatsapp::SwitchAccount::SameNumberGuard)
  end
  unless Whatsapp::ReauthorizationService <= Whatsapp::SwitchAccount::KeepInboxName
    Whatsapp::ReauthorizationService.prepend(Whatsapp::SwitchAccount::KeepInboxName)
  end
  unless Api::V1::Accounts::Whatsapp::AuthorizationsController <= Whatsapp::SwitchAccount::AuthorizationResponse
    Api::V1::Accounts::Whatsapp::AuthorizationsController.prepend(Whatsapp::SwitchAccount::AuthorizationResponse)
  end
end
