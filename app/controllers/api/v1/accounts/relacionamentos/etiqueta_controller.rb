# "Etiquetar" da Lista nova de Relacionamentos (#2894): a etiqueta em cada pessoa marcada, para quem pode editar contatos.
class Api::V1::Accounts::Relacionamentos::EtiquetaController < Api::V1::Accounts::Relacionamentos::AcaoEmGrupoController
  CAMPOS = %w[pessoa_ids etiqueta].freeze

  def create
    authorize Contact, :update?
    pedido = corpo(params.permit(:etiqueta, pessoa_ids: []))
    render json: ::Relacionamentos::AplicarEtiqueta.new(**de_quem_pede, **pedido).call
  end
end
