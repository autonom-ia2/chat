# frozen_string_literal: true

# #2711 — a pessoa troca o telefone do contato e a caixa WAHA passa a mandar ao número novo. Ver
# Waha::TrocaDeTelefoneNaMao. Prepend no fork; o controller do Chatwoot fica intacto.
Rails.application.config.to_prepare do
  controller = Api::V1::Accounts::ContactsController
  controller.prepend(Waha::TrocaDeTelefoneNaMao) unless controller <= Waha::TrocaDeTelefoneNaMao
end
