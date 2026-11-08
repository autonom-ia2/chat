# frozen_string_literal: true

# #1934 — foto de perfil do contato pela sessão WAHA da caixa híbrida. Ver WhatsappHybrid::FotoDoContato.
Rails.application.config.to_prepare do
  if Message._commit_callbacks.none? { |callback| callback.filter == WhatsappHybrid::FotoDoContato }
    Message.after_commit WhatsappHybrid::FotoDoContato, on: :create
  end
end
