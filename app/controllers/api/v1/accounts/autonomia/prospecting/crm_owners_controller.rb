# "Com quem fica" da Prospecção nova (#2694): as pessoas da conta que podem receber o card no funil escolhido. Pessoas,
# não funções. Só para quem pode criar card e escolher o dono (a chave de funis, CrmCardOwner.can_choose?), num funil
# que a própria pessoa enxerga. O CRM tem o owner_options, mas ele responde por caixa e funil, e o card da Prospecção
# nasce sem caixa: lá todo mundo passaria.
class Api::V1::Accounts::Autonomia::Prospecting::CrmOwnersController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  before_action :authorize_crm_card_create!
  before_action :authorize_crm_owner_choice!

  def index
    owners = ::Autonomia::Prospecting::CrmCardOwner.new(account: Current.account, user: Current.user, pipeline: pipeline).options
    render json: { payload: owners.map { |owner| { id: owner.id, name: owner.name } } }
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound
    render_crm_send_error('pipeline_not_found', status: :not_found)
  end

  private

  def pipeline
    ::Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account, account_user: Current.account_user)
                                   .apply(Current.account.crm_pipelines).active.find(params.require(:pipeline_id))
  end
end
