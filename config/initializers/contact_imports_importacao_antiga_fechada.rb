# frozen_string_literal: true

# #2772 — com a importação nova de contatos ligada, a rota antiga do Chatwoot (POST contacts/import) fecha. Ver
# ContactImports::ImportacaoAntigaFechada. Prepend no fork; o controller do Chatwoot fica intacto.
Rails.application.config.to_prepare do
  controller = Api::V1::Accounts::ContactsController
  controller.prepend(ContactImports::ImportacaoAntigaFechada) unless controller <= ContactImports::ImportacaoAntigaFechada
end
