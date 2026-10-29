# Gerenciador simples (#2198, PR 1, flag `meta_ads_criar`). Sem a flag, 404: nada aqui chama a Meta.
#
# GET   meta_ads_connection/create_options    → o que a pessoa escolhe para criar (Crm::MetaAds::Creation::Options).
# GET   meta_ads_connection/boost_posts       → ?page_id= → posts da Página e do Instagram dela para impulsionar
#                                               (PR 2, #2339) → { posts, instagram_posts, posts_error }.
# POST  meta_ads_connection/media             → foto ou vídeo do celular → { kind, hash | video_id }.
# POST  meta_ads_connection/ads               → anúncio novo ou post impulsionado (`kind: post`), sempre pausado →
#                                               { ad_id, name, status, budget }.
# GET   meta_ads_connection/ads/:ad_id/budget → orçamento e datas; falha é erro, nunca vazio.
# PATCH meta_ads_connection/ads/:ad_id/budget → { amount, end_time } → orçamento novo.
# GET   meta_ads_connection/paused_ads        → anúncios criados aqui que seguem pausados.
#
# Ver orçamento e pausados: administrador ou `meta_ads_view`. As opções de criar (Páginas, Instagram, números do
# WhatsApp e fotos da conta de anúncios), os posts para impulsionar, criar, subir mídia e mudar orçamento: administrador ou `meta_ads_manage`. O
# que muda fica na Auditoria da conta com quem fez (nunca o token). Sem conexão ativa com conta de anúncios: 404
# not_connected.
class Api::V1::Accounts::Crm::MetaAdsCreationController < Api::V1::Accounts::Crm::BaseController
  CREATED_ACTION = 'meta_ads_ad_created'.freeze
  BUDGET_ACTION = 'meta_ads_budget_change'.freeze
  NOT_FOUND_CODES = %w[ad_not_found budget_not_found].freeze

  before_action :ensure_feature
  before_action :ensure_view
  before_action :ensure_manage, only: [:options, :boost_posts, :media, :create, :update_budget]
  before_action :load_connection

  rescue_from ::Crm::MetaAds::Creation::Error, with: :render_creation_error

  def options
    render json: { options: ::Crm::MetaAds::Creation::Options.new(Current.account, @connection).payload }
  end

  def boost_posts
    render json: ::Crm::MetaAds::Creation::Options.new(Current.account, @connection).boost_posts(params[:page_id].to_s)
  end

  def media
    file = params[:file]
    return render_unprocessable('invalid_media') unless file.respond_to?(:path)

    render json: { media: ::Crm::MetaAds::Creation::Media.new(@connection).upload!(file) }
  end

  def create
    service = ::Crm::MetaAds::Creation::NewAd.new(@connection, user: Current.user)
    created = service.create!(create_params)
    audit!(CREATED_ACTION, 'ad_id' => created[:ad_id], 'ad_name' => created[:name], 'budget' => created[:budget]) if service.created_now
    render json: created
  end

  def budget
    render json: { budget: ::Crm::MetaAds::Creation::Budget.new(@connection).read(params[:ad_id].to_s) }
  end

  def update_budget
    change = ::Crm::MetaAds::Creation::Budget.new(@connection)
                                             .change!(params[:ad_id].to_s, amount: params[:amount], end_time: params[:end_time])
    audit_budget!(*change.values_at(:before, :after))
    render json: { budget: change[:after] }
  rescue ::Crm::MetaAds::Creation::Error => e
    # Parou no meio e não deu para desfazer: a Auditoria registra o que ficou mudado na Meta.
    audit!(BUDGET_ACTION, 'ad_id' => params[:ad_id].to_s, 'partial' => e.details) if e.code == 'meta_partial'
    raise
  end

  def paused
    render json: { ads: ::Crm::MetaAds::Creation::PausedAds.new(@connection).list }
  end

  private

  def create_params
    params.permit(:kind, :post_source, :post_id, :idempotency_key, :name, :destination, :page_id, :whatsapp_number, :site_url,
                  :site_action, :text, :headline, :ready_message, :placement, :region, :age_min, :age_max, :special_category,
                  :daily_amount, :start_date, :end_date, :recreate_unconfirmed,
                  states: [], media: [:kind, :hash, :video_id, :image_hash], cards: [:kind, :hash, :video_id, :image_hash]).to_h
  end

  def ensure_feature
    head :not_found unless Current.account.feature_enabled?('meta_ads_criar')
  end

  def ensure_view
    render json: { error: 'forbidden' }, status: :forbidden unless policy.show?
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless policy.update?
  end

  def policy
    @policy ||= Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection)
  end

  def load_connection
    @connection = ::Crm::MetaAdsConnection.active.find_by(account_id: Current.account.id)
    render json: { error: 'not_connected' }, status: :not_found if @connection&.ad_account_id.blank?
  end

  def render_creation_error(error)
    return render json: { error: error.code }, status: :not_found if NOT_FOUND_CODES.include?(error.code)

    body = { error: error.code, idempotency_key: error.attempt_key }.compact
    return render json: body, status: :conflict if error.code == 'in_progress'

    body[:nothing_created] = error.nothing_created if action_name == 'create'
    render json: body, status: :unprocessable_entity
  end

  def audit_budget!(before, after)
    audit!(BUDGET_ACTION, 'ad_id' => params[:ad_id].to_s, 'level' => before[:level], 'object_id' => before[:object_id],
                          'amount' => [before[:amount], after[:amount]], 'end_time' => [before[:end_time], after[:end_time]])
  end

  # A Meta já mudou quando isto roda: falha ao gravar vai para o rastreador de erros e a resposta continua dizendo a
  # verdade (como no Crm::MetaAdsAdManagementController).
  def audit!(action, changes)
    Audited.audit_class.create!(auditable: Current.account, user: Current.user, action: action, audited_changes: changes)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
