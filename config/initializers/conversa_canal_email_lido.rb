# frozen_string_literal: true

# #1870 — "lido" do e-mail sincronizado nos dois sentidos com o servidor IMAP do cliente (flag email_lido_sincronizado).
# Prepends próprios; o controller e a importação do Chatwoot ficam intactos. Ver ConversaCanal::LidoNoServidorDoEmail e
# ConversaCanal::LidoNaImportacaoDoEmail.
Rails.application.config.to_prepare do
  conversas = Api::V1::Accounts::ConversationsController
  conversas.prepend(ConversaCanal::LidoNoServidorDoEmail) unless conversas <= ConversaCanal::LidoNoServidorDoEmail
  importacao = Imap::BaseFetchEmailService
  importacao.prepend(ConversaCanal::LidoNaImportacaoDoEmail) unless importacao <= ConversaCanal::LidoNaImportacaoDoEmail
end
