# "Apagar" da Lista nova de Relacionamentos (#2894): apaga as pessoas marcadas, só para quem pode apagar contatos
# (administrador ou a chave contact_delete da função).
class Api::V1::Accounts::Relacionamentos::ApagarController < Api::V1::Accounts::Relacionamentos::AcaoEmGrupoController
  CAMPOS = %w[pessoa_ids].freeze

  def create
    authorize Contact, :destroy?
    pedido = corpo(params.permit(pessoa_ids: []))
    render json: ::Relacionamentos::Apagar.new(**de_quem_pede, **pedido).call
  end
end
