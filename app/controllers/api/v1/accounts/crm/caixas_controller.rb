# Caixas no CRM (#1149): a tela CRM → Caixas no CRM. Listar as caixas, abrir uma e salvar a caixa inteira de uma vez.
class Api::V1::Accounts::Crm::CaixasController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_inbox, only: [:show, :update]

  def index
    authorize ::Crm::InboxAgentAccess, :index?
    retrato = ::Crm::Caixas::Retrato.new(account: Current.account, inboxes: Current.account.inboxes.order(:name))
    render json: { payload: { caixas: retrato.caixas, funis: retrato.funis } }
  end

  def show
    authorize ::Crm::InboxAgentAccess, :index?
    render_caixa
  end

  def update
    authorize ::Crm::InboxAgentAccess, :update?
    ::Crm::Caixas::Gravador.new(account: Current.account, inbox: @inbox, user: Current.user, dados: caixa_params).perform
    render_caixa
  rescue ::Crm::Caixas::Gravador::Invalida => e
    render json: { error: { code: e.code } }, status: :unprocessable_entity
  end

  private

  def render_caixa
    retrato = ::Crm::Caixas::Retrato.new(account: Current.account, inboxes: [@inbox])
    render json: { payload: { caixa: retrato.caixa(@inbox), funis: retrato.funis } }
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def caixa_params
    parameter_set(:caixa).permit(:modo, :default_stage_id, pipeline_ids: [],
                                                           people: [:id, :triage, :only_own, { pipeline_ids: [] }])
  end
end
