# frozen_string_literal: true

# #1941 — a nota técnica do conector WAHA ("Não foi possível receber uma mensagem") vira um aviso curto e humano.
# Ver Waha::NotaDoConector.
Rails.application.config.to_prepare do
  Message.before_create Waha::NotaDoConector if Message._create_callbacks.none? { |callback| callback.filter == Waha::NotaDoConector }
end
