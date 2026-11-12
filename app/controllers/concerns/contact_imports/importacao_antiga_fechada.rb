# #2772 — prepend em Api::V1::Accounts::ContactsController#import.
#
# A importação antiga do Chatwoot (`POST contacts/import` → DataImportJob → DataImport::ContactManager) sobrescreve o
# telefone, o nome e o e-mail de contato que já existe. A regra do Rodrigo (G24, #2771) é que a importação não
# sobrescreve. Com a importação nova ligada (ContactImports::Config, que só preenche campo vazio), a tela já leva para
# ela (contactImport.routes.js, openContactImport); aqui a rota antiga também fecha, para um pedido direto à API não
# passar pelo caminho que sobrescreve. Com a nova desligada, a antiga segue como no Chatwoot.
#
# Mora em app/controllers/concerns porque é código do controller: o gerador de formatos do Guia (#900) só lê os
# controllers, e fora daqui o override escondia o `import_file` da action do Chatwoot.
module ContactImports::ImportacaoAntigaFechada
  def import
    return super unless ContactImports::Config.enabled?

    render json: { error: I18n.t('contact_imports.legacy_import_closed') }, status: :unprocessable_entity
  end
end
