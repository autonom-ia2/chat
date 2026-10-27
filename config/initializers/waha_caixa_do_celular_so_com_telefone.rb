# frozen_string_literal: true

# #2211 — contato sem telefone não recebe pelo WhatsApp do celular (caixa API ligada ao WAHA). Ver
# Waha::CaixaDoCelularSoComTelefone.
Rails.application.config.to_prepare do
  servico = Contacts::ContactableInboxesService
  servico.prepend(Waha::CaixaDoCelularSoComTelefone) unless servico <= Waha::CaixaDoCelularSoComTelefone
end
