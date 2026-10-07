# Conexão da conta com os anúncios da Meta (#1034, #1047). Só administrador.
#
# GET    → estado da conexão (nunca o token), dados do portfólio parceiro da plataforma e se algum funil
#          ligado ao WhatsApp oficial já avisa a Meta das vendas.
# PUT    → modo `token`: testa o token colado (ads_read concedido e ao menos uma conta de anúncios) e grava.
# DELETE → apaga a conexão. Os nomes já resolvidos ficam nos toques e no cache.
#
# Conexão guiada (#1047):
# GET   ad_accounts?mode=  → contas de anúncios que esta conta pode usar, a recomendada primeiro
# GET   pixels?mode=&ad_account_id= → Pixels da conta de anúncios
# POST  selection    → lê a conta e o Pixel de verdade e só então grava (CA-1.2)
# PATCH destinations → para onde os anúncios levam: WhatsApp, site ou os dois
# GET   funnels        → funis ligados ao WhatsApp oficial, com o que falta para avisar a Meta (passo 4)
# PATCH funnel         → grava o tipo de cada etapa e liga o aviso no funil; enabled=false para de avisar
# POST  suggest_stages → a IA sugere o tipo de cada etapa (assíncrono, como as outras ações de IA do CRM)
#
# Coleta (#1073):
# POST  insights → último dia lido da conta de anúncios; pede a leitura de hoje se tiver mais de 5 minutos.
#                  O fim da leitura chega pelo canal de tempo real (crm.meta_ads.insights_updated).
#
# Painel (#1088):
# GET   panel?days=7|30 → o painel do dia a dia (Crm::MetaAds::Panel::Report); também pede a leitura de hoje.
# GET   panel_ad?ad_id=&days=7|30 → um anúncio por dentro (Crm::MetaAds::Panel::AdDetail). Só banco: abrir o
#       anúncio não chama a Meta nem pede leitura (o painel por trás já pediu).
#
# Quem não é administrador recebe 403 (não 401: a sessão é válida, só falta a permissão).
class Api::V1::Accounts::Crm::MetaAdsConnectionsController < Api::V1::Accounts::Crm::BaseController
  include DeferInteractiveAi

  # Tokens da Meta têm algumas centenas de caracteres; o teto barra corpos absurdos antes da Graph.
  MAX_TOKEN_LENGTH = 2048
  READ_ACTIONS = %w[show ad_accounts pixels funnels insights panel panel_ad].freeze

  before_action :ensure_administrator
  before_action :ensure_mode, only: [:ad_accounts, :pixels, :selection]

  def show
    render json: payload
  end

  def update
    token = connection_params[:access_token].to_s.strip
    return render_unprocessable('access_token_required') if token.blank?
    return render_unprocessable('access_token_too_long') if token.length > MAX_TOKEN_LENGTH
    return render_unprocessable('encryption_not_configured') unless Chatwoot.encryption_configured?

    error = token_error(Meta::AdsGraphClient.new(access_token: token))
    return render_unprocessable(error) if error

    save_connection!(token)
    Crm::MetaAds::BackfillJob.perform_later(Current.account.id)
    render json: payload
  end

  def destroy
    current_connection&.destroy!
    render json: payload
  end

  def insights
    connection = current_connection
    return render json: { insights: nil } if connection.blank?

    refreshing = ::Crm::MetaAds::Insights::Refresh.request!(connection)
    render json: { insights: ::Crm::MetaAds::Insights::Summary.payload(connection, refreshing: refreshing) }
  end

  def panel
    connection = current_connection
    return render json: { panel: nil } if connection.blank? || connection.ad_account_id.blank?

    refreshing = ::Crm::MetaAds::Insights::Refresh.request!(connection)
    report = ::Crm::MetaAds::Panel::Report.new(connection, days: params[:days]).payload
    render json: { panel: report.merge(synced_at: connection.reload.insights_synced_at, refreshing: refreshing) }
  end

  def panel_ad
    connection = current_connection
    return render json: { ad: nil } if connection.blank? || connection.ad_account_id.blank?

    render json: { ad: ::Crm::MetaAds::Panel::AdDetail.new(connection, ad_id: params[:ad_id], days: params[:days]).payload }
  end

  def ad_accounts
    render json: { ad_accounts: setup.ad_accounts(params[:mode]) }
  rescue Crm::MetaAds::Setup::Error => e
    render_unprocessable(e.code)
  end

  def pixels
    render json: { pixels: setup.pixels(params[:mode], params[:ad_account_id].to_s) }
  rescue Crm::MetaAds::Setup::Error => e
    render_unprocessable(e.code)
  end

  def selection
    setup.select!(mode: params[:mode], ad_account_id: params[:ad_account_id].to_s, pixel_id: params[:pixel_id].presence&.to_s)
    render json: payload
  rescue Crm::MetaAds::Setup::Error => e
    render_unprocessable(e.code)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    render_unprocessable('ad_account_in_use')
  end

  def destinations
    connection = current_connection
    return render_unprocessable('not_connected') if connection.blank?

    bool = ActiveModel::Type::Boolean.new
    values = ::Crm::MetaAdsConnection::DESTINATIONS.index_with { |key| bool.cast(params.dig(:destinations, key)) == true }
    connection.update!(destinations: values)
    render json: payload
  end

  def funnels
    render json: funnels_service.payload
  end

  def funnel
    return render_unprocessable('not_connected') if current_connection.blank?

    pipeline = funnels_service.find!(params[:pipeline_id])
    if ActiveModel::Type::Boolean.new.cast(params[:enabled]) == false
      funnels_service.disable!(pipeline)
    else
      funnels_service.apply!(pipeline, stage_types_param)
    end
    render json: ::Crm::MetaAds::Funnels.new(Current.account, current_connection).payload
  rescue ::Crm::MetaAds::Funnels::Error => e
    render_unprocessable(e.code)
  end

  def suggest_stages
    return render_unprocessable('ai_unavailable') unless ::Crm::Ai::Config.enabled?

    funnels_service.find!(params[:pipeline_id])
    defer_interactive_ai('meta_funnel_stages', { pipeline_id: params[:pipeline_id].to_i, language: I18n.locale.to_s })
  rescue ::Crm::MetaAds::Funnels::Error => e
    render_unprocessable(e.code)
  end

  private

  def ensure_administrator
    action = policy_action
    return if Pundit.policy!(pundit_user, ::Crm::MetaAdsConnection).public_send(action)

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def policy_action
    return :show? if READ_ACTIONS.include?(action_name)

    action_name == 'destroy' ? :destroy? : :update?
  end

  def ensure_mode
    render_unprocessable('invalid_mode') unless ::Crm::MetaAdsConnection::MODES.include?(params[:mode])
  end

  # Ordem: a Meta respondeu? o token vale? tem ads_read? enxerga alguma conta de anúncios?
  # Sem conta atribuída o token "funciona", mas nenhum nome aparece: melhor recusar já aqui.
  def token_error(client)
    permissions = client.permissions
    return graph_failure(permissions) unless permissions.ok
    return 'missing_ads_read' unless Meta::AdsGraphClient.ads_read_granted?(permissions.data)

    accounts = client.ad_accounts_sample
    return graph_failure(accounts) unless accounts.ok

    'no_ad_account' if Array(accounts.data.to_h['data']).empty?
  end

  def graph_failure(result)
    return 'meta_unavailable' if result.transient?
    return 'missing_ads_read' if result.scope_error?

    'invalid_token'
  end

  # Colar um token novo volta a conexão ao modo `token`; a conta de anúncios escolhida antes só continua
  # se o novo token também a enxergar, o que a escolha seguinte confere.
  def save_connection!(token)
    connection = ::Crm::MetaAdsConnection.find_or_initialize_by(account_id: Current.account.id)
    connection.update!(access_token: token, mode: 'token', status: 'active', last_checked_at: Time.current, last_error: nil)
  end

  def setup
    @setup ||= ::Crm::MetaAds::Setup.new(Current.account)
  end

  def current_connection
    ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end

  def payload
    connection = current_connection
    ::Crm::MetaAdsConnection.public_payload_for(connection).merge(
      partner: ::Crm::MetaAds::Platform.public_payload,
      whatsapp_portfolio: setup.portfolio_ids.any?,
      # Portfólio do cliente na Meta: o "Abrir a Meta" do passo 1 cai direto em Parceiros dele (#1068).
      client_portfolio_id: setup.portfolio_ids.first,
      sales_signal: { enabled: ::Crm::MetaAds::Funnels.new(Current.account, connection).sales_enabled? }
    )
  end

  def funnels_service
    @funnels_service ||= ::Crm::MetaAds::Funnels.new(Current.account, current_connection)
  end

  # { stage_id => tipo }: 'lead', 'qualified', 'opportunity', 'negotiation' ou 'none'.
  def stage_types_param
    params.permit(stages: [:id, :funnel_stage_type]).fetch(:stages, []).to_h { |row| [row[:id], row[:funnel_stage_type].to_s] }
  end

  def connection_params
    parameter_set(:meta_ads_connection).permit(:access_token)
  end
end
