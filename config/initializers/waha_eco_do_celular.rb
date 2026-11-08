# frozen_string_literal: true

# #1941 — eco do celular na caixa WAHA comum: texto sem o prefixo do conector e autor congelado. Ver Waha::EcoDoCelular.
# Roda antes dos callbacks de whatsapp_rich_native.rb (ordem dos arquivos). Nenhum deles tira `c2y_phone_author_id`;
# quem a tira é só a API pública (Waha::RichNative::ForgeryGuard), antes da criação.
Rails.application.config.to_prepare do
  Message.before_create Waha::EcoDoCelular if Message._create_callbacks.none? { |callback| callback.filter == Waha::EcoDoCelular }
end
