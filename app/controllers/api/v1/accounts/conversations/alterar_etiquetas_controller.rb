# #2202 (PR 3) — pôr e tirar etiquetas da conversa uma a uma (AlterarEtiquetasConcern). Quem pode é quem opera a
# conversa, como na rota de sempre (BaseController: show?).
class Api::V1::Accounts::Conversations::AlterarEtiquetasController < Api::V1::Accounts::Conversations::BaseController
  include AlterarEtiquetasConcern

  private

  def model
    @conversation
  end

  def vista_das_etiquetas
    'api/v1/accounts/conversations/labels/create'
  end
end
