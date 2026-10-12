# Caixas no CRM (#1149): a tela CRM → Caixas no CRM. Listar as caixas, abrir uma e salvar a caixa inteira de uma vez.
class Api::V1::Accounts::Crm::CaixasController < Api::V1::Accounts::Crm::BaseController
  # A flag por conta protege a API também, não só a rota do painel: sem ela, nada aqui grava acesso por funil.
  before_action :ensure_caixas_enabled
  before_action :authorize_index, only: [:index, :show]
  before_action :authorize_update, only: [:update]
  before_action :fetch_inbox, only: [:show, :update]

  def index
    retrato = ::Crm::Caixas::Retrato.new(account: Current.account, inboxes: Current.account.inboxes.order(:name))
    render json: { payload: { caixas: retrato.caixas, funis: retrato.funis } }
  end

  def show
    render_caixa
  end

  def update
    ::Crm::Caixas::Gravador.new(account: Current.account, inbox: @inbox, user: Current.user, dados: caixa_params).perform
    render_caixa
  rescue ::Crm::Caixas::Gravador::Invalida => e
    render json: { error: { code: e.code } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    # Dois salvamentos da mesma caixa ao mesmo tempo: o segundo pede para recarregar.
    render json: { error: { code: 'crm.caixas.conflito' } }, status: :conflict
  end

  private

  def ensure_caixas_enabled
    render json: { error: 'crm.caixas.disabled' }, status: :not_found unless Current.account.feature_enabled?('crm_configurar_caixas')
  end

  def authorize_index
    authorize ::Crm::InboxAgentAccess, :index?
  end

  def authorize_update
    authorize ::Crm::InboxAgentAccess, :update?
  end

  def render_caixa
    retrato = ::Crm::Caixas::Retrato.new(account: Current.account, inboxes: [@inbox])
    render json: { payload: { caixa: retrato.caixa(@inbox), funis: retrato.funis } }
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def caixa_params
    params.require(:caixa).permit(:modo, :default_stage_id, :legado,
                                  pipeline_ids: [], people: [:id, :triage, :only_own, { pipeline_ids: [] }])
  end
end
