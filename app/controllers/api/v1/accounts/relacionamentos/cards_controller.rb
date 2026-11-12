# "Criar cards" da Lista nova de Relacionamentos (#2894): um card por pessoa marcada, para quem pode criar card no CRM.
class Api::V1::Accounts::Relacionamentos::CardsController < Api::V1::Accounts::Relacionamentos::AcaoEmGrupoController
  CAMPOS = %w[pessoa_ids funil_id etapa_id].freeze

  def create
    authorize ::Crm::Card, :create?
    pedido = corpo(params.permit(:funil_id, :etapa_id, pessoa_ids: []))
    render json: ::Relacionamentos::CriarCards.new(**de_quem_pede, **pedido).call
  end
end
