# Os campos de um link novo de Links e QR codes (QR/link direto ou página do site). Um lugar só para a regra, usado
# por Links e QR codes e por Anúncios › Destino (#2338), que liga a página do site ali mesmo. Quem grava é o
# controller (`Ctwa::TrackedLink.create!`), para o Guia achar o modelo do corpo (#900).
#
# `usage` só na criação; texto pré-preenchido só existe no QR/link direto — no modo site o texto é da página
# (cotação + código).
module Ctwa::TrackedLinkAttributes
  module_function

  def for_create(account:, inbox:, params:)
    usage = params[:usage].presence || 'direct'
    attributes = { account: account, inbox: inbox, name: params[:name], usage: usage }
    attributes[:prefilled_text] = params[:prefilled_text] if usage == 'direct'
    attributes[:allowed_origins] = Array(params[:allowed_origins]) if params.key?(:allowed_origins)
    attributes
  end
end
