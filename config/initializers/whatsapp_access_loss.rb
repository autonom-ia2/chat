# frozen_string_literal: true

# #2907 — Caixa do WhatsApp que perde o acesso à conta da Meta não cai mais em silêncio. Prepends do fork; os arquivos do
# Chatwoot ficam intactos.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  # `code 100, subcode 33` (sem acesso ao número/WABA) conta como erro de autorização, como o `190`.
  prepend_once.call(Whatsapp::HealthService::ApiError, Whatsapp::AccessLoss::ApiErrorCheck)
  # A checagem de saúde marca "precisa reconectar" no segundo erro seguido e apaga quando o acesso volta.
  prepend_once.call(Whatsapp::HealthService, Whatsapp::AccessLoss::HealthCheck)
  # Perda de acesso confirmada: o Guia avisa os administradores (conversa do Guia, sino, push e e-mail), uma vez por queda.
  prepend_once.call(Channel::Whatsapp, Whatsapp::AccessLoss::GuideAlert)
  # O aviso `account_update` da Meta (parceiro removido, conta apagada, coexistência desfeita) marca na hora.
  prepend_once.call(Webhooks::WhatsappController, Whatsapp::AccessLoss::WebhookEntry)
end
