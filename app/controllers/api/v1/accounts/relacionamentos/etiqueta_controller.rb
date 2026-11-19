# "Etiquetar" da Lista nova de Relacionamentos (#2894): as etiquetas em cada pessoa marcada, para quem pode editar
# contatos. #3062 — várias de uma vez, e "Tirar etiquetas" das marcadas, com a mesma regra.
class Api::V1::Accounts::Relacionamentos::EtiquetaController < Api::V1::Accounts::Relacionamentos::AcaoEmGrupoController
  CAMPOS = %w[pessoa_ids etiquetas].freeze

  def create
    responder(::Relacionamentos::AplicarEtiqueta)
  end

  def tirar
    responder(::Relacionamentos::TirarEtiqueta)
  end

  private

  def responder(acao)
    authorize Contact, :update?
    pedido = corpo(params.permit(pessoa_ids: [], etiquetas: []))
    render json: acao.new(**de_quem_pede, **pedido).call
  end
end
