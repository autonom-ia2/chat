# Anúncios da Meta › Formulários (#2195, flag `meta_ads_formularios`). Sem a flag, 404: nada aqui chama a Meta.
#
# GET    meta_ads_lead_forms                          → Páginas, formulários, funis que a pessoa enxerga e quem chegou.
# POST   meta_ads_lead_forms/pages/:page_id/receive   → liga a Página (assina o leadgen).
# DELETE meta_ads_lead_forms/pages/:page_id/receive   → para (tira só o leadgen; os destinos ficam).
# PUT    meta_ads_lead_forms/forms/:form_id/destination → funil e etapa do formulário; import_past traz os últimos 90 dias.
# DELETE meta_ads_lead_forms/forms/:form_id/destination → tira o funil do formulário.
# POST   meta_ads_lead_forms/forms/:form_id/bring_past  → formulário arquivado: traz quem preencheu, sem destino.
# Trazer quem já preencheu roda em segundo plano (importing: true); quantos entraram fica na Auditoria.
#
# Acesso (parecer da sessão Funções, 27/10): ver pede `meta_ads_view`; a lista de quem chegou (nome, telefone, e-mail)
# pede também `contact_view`. Escrever pede `meta_ads_manage`. O funil tem de ser um que a pessoa enxerga (mesmo filtro
# do Kanban) e a etapa tem de ser dele. Trazer quem já preencheu cria cards em lote: pede também criar card no CRM.
# Cada ligar, parar, destino e "trazer" fica na Auditoria da conta, sem token.
# Abrir a tela só para ver não grava Página: as Páginas lidas só ficam guardadas para quem tem `meta_ads_manage` (#2357).
class Api::V1::Accounts::Crm::MetaAdsLeadFormsController < Api::V1::Accounts::Crm::BaseController
  FEATURE = 'meta_ads_formularios'.freeze
  NOT_FOUND_CODES = %w[page_not_found form_not_found].freeze

  before_action :ensure_feature
  before_action :ensure_view
  before_action :load_manage_access
  before_action :ensure_manage, except: [:index]
  before_action :load_connection
  before_action :ensure_current_destination_visible, only: [:save_destination, :remove_destination]
  before_action :load_destination, only: [:save_destination, :bring_past]
  before_action :ensure_create_cards, only: [:bring_past]

  rescue_from ::Crm::MetaAds::LeadForms::Error, with: :render_lead_forms_error
  rescue_from ::Crm::MetaAds::LeadForms::Unavailable, with: :render_unavailable

  def index
    render json: payload
  end

  def receive
    hub.receive!(params[:page_id])
    audit!('meta_ads_lead_page_receive', 'page_id' => params[:page_id].to_s, 'page_name' => hub.page_name(params[:page_id]))
    render json: payload
  end

  def stop
    hub.stop!(params[:page_id])
    audit!('meta_ads_lead_page_stop', 'page_id' => params[:page_id].to_s, 'page_name' => hub.page_name(params[:page_id]))
    render json: payload
  end

  def save_destination
    return unless import_past? ? ensure_create_cards : true

    result = hub.save_destination!(params[:form_id], pipeline: @pipeline, stage: @stage, import_past: import_past?)
    audit!('meta_ads_lead_form_destination', destination_changes.merge('importing' => result[:importing]))
    render json: result
  end

  def remove_destination
    hub.remove_destination!(params[:form_id])
    audit!('meta_ads_lead_form_destination_removed', 'form_id' => params[:form_id].to_s)
    head :no_content
  end

  def bring_past
    result = hub.bring_past!(params[:form_id], pipeline: @pipeline, stage: @stage)
    audit!('meta_ads_lead_form_bring_past', destination_changes.merge('importing' => true))
    render json: result
  end

  private

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?(FEATURE)
  end

  def ensure_view
    render json: { error: 'forbidden' }, status: :forbidden unless connection_policy.show?
  end

  def load_manage_access
    @can_manage = connection_policy.update?
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless @can_manage
  end

  # Quem não cria card à mão não cria em lote.
  def ensure_create_cards
    return true if Pundit.policy!(pundit_user, ::Crm::Card).create?

    render json: { error: 'forbidden' }, status: :forbidden
    false
  end

  def connection_policy
    @connection_policy ||= Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection)
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render json: { error: 'not_connected' }, status: :not_found if @connection.nil?
  end

  # Quem não enxerga o funil para onde o formulário manda gente não troca nem tira esse destino.
  def ensure_current_destination_visible
    current = ::Crm::MetaAdsLeadForm.find_by(account_id: Current.account.id, form_id: params[:form_id].to_s)&.pipeline_id
    return if current.nil? || visible_pipelines(Current.account.crm_pipelines).exists?(id: current)

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def load_destination
    @pipeline = visible_pipelines.find_by(id: params[:pipeline_id])
    @stage = @pipeline && selectable_stages(@pipeline).find_by(id: params[:stage_id])
    render_unprocessable('invalid_destination') if @stage.nil?
  end

  def import_past?
    ActiveModel::Type::Boolean.new.cast(params[:import_past]) || false
  end

  def hub
    @hub ||= ::Crm::MetaAds::LeadForms::Hub.new(
      connection: @connection, account: Current.account, user: Current.user, remember_pages: @can_manage
    )
  end

  def payload
    hub.payload(pipelines: pipelines_payload, visible_cards: show_leads? ? visible_cards : nil,
                visible_pipeline_ids: visible_pipelines(Current.account.crm_pipelines).pluck(:id))
  end

  # Mesmo acesso do Kanban: funis que a pessoa enxerga e, nas caixas com restrição, só os cards dela.
  def visible_cards
    cards = Current.account.crm_cards.where(pipeline_id: visible_pipelines.select(:id))
    ::Crm::Access::CardScope.new(user: Current.user, account: Current.account, account_user: Current.account_user).apply(cards)
  end

  def show_leads?
    Current.account_user&.permission_granted?('contact_view') || false
  end

  # Para escolher destino, só os ativos; para ver ou tirar um destino que já existe, também os arquivados.
  def visible_pipelines(scope = Current.account.crm_pipelines.active)
    access = ::Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    access.apply(scope)
  end

  # Etapa de ganho ou perda não recebe gente nova.
  def selectable_stages(pipeline)
    pipeline.stages.where(is_won_stage: false, is_lost_stage: false)
  end

  def pipelines_payload
    visible_pipelines.order(:id).includes(:stages).map do |pipeline|
      stages = pipeline.stages.reject { |stage| stage.is_won_stage || stage.is_lost_stage }.sort_by(&:position)
      { id: pipeline.id, name: pipeline.name, stages: stages.map { |stage| { id: stage.id, name: stage.name } } }
    end
  end

  def destination_changes
    { 'form_id' => params[:form_id].to_s, 'pipeline_id' => @pipeline.id, 'pipeline_name' => @pipeline.name,
      'stage_id' => @stage.id, 'stage_name' => @stage.name }
  end

  # A Meta não respondeu agora: tente de novo.
  def render_unavailable(error)
    render json: { error: error.code }, status: :service_unavailable
  end

  def render_lead_forms_error(error)
    return render json: { error: error.code }, status: :not_found if NOT_FOUND_CODES.include?(error.code)

    render_unprocessable(error.code)
  end

  # O log da aplicação não sobrevive ao deploy: ligar a Página e criar cards em lote ficam na Auditoria da conta.
  # A Meta já mudou quando isto roda: falha ao gravar vai para o rastreador e a resposta continua dizendo a verdade.
  def audit!(action, changes)
    Audited.audit_class.create!(auditable: Current.account, user: Current.user, action: action, audited_changes: changes.compact)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
