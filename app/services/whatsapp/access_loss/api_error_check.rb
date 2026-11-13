# #2907 — Perda de acesso à conta do WhatsApp conta como erro de autorização.
#
# Quando a empresa tira o acesso do nosso app (Plataforma comercial no app WhatsApp Business, ou o Gerenciador), o token
# continua válido, mas a Graph responde `code 100, error_subcode 33` ("does not exist, cannot be loaded due to missing
# permissions") para o número e para a WABA. O Chatwoot só tratava `code 190` como autorização: a caixa caía em silêncio e
# a Saúde da conta mostrava o erro cru, sem o botão de reconectar. Prepended em `Whatsapp::HealthService::ApiError`.
module Whatsapp::AccessLoss::ApiErrorCheck
  OBJECT_NOT_ACCESSIBLE = { code: 100, subcode: 33 }.freeze

  def authorization_error?
    super || access_lost?
  end

  def access_lost?
    code.to_i == OBJECT_NOT_ACCESSIBLE[:code] && subcode.to_i == OBJECT_NOT_ACCESSIBLE[:subcode]
  end
end
