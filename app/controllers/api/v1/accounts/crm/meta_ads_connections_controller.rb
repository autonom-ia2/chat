# Conexão da conta com os anúncios da Meta (#1034, #1047). Só administrador.
#
# GET    → estado da conexão (nunca o token), dados do portfólio parceiro da plataforma e se algum funil
#          ligado ao WhatsApp oficial já avisa a Meta das vendas.
# PUT    → modo `token`: testa o token colado (ads_read concedido e ao menos uma conta de anúncios) e grava.
# DELETE → apaga a conexão. Os nomes já resolvidos ficam nos toques e no cache.
# POST facebook_login → modo `facebook_login` (#1069): troca o código do "Entrar com Facebook" por token,
#                       testa como o PUT e grava. A escolha da conta segue pelo passo 2 com mode=facebook_login.
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
#       F5 (#1110): mais o consultor (`advice`, até 3 ações, sempre de 30 dias), a Meta × nós do período
#       (`meta_comparison`) e o tempo de resposta do período (`response_time`).
# GET   panel_ad?ad_id=&days=7|30 → um anúncio por dentro (Crm::MetaAds::Panel::AdDetail). Só banco: abrir o
#       anúncio não chama a Meta nem pede leitura (o painel por trás já pediu).
# GET   panel_list?step=conversations|quotes|sales|slow_replies&days=7|30 → a lista por trás de cada etapa do
#       caminho do dinheiro (Crm::MetaAds::Panel::PathList, F5). Só banco. Etapa fora da lista: 422 invalid_step.
#
# Quem não é administrador recebe 403 (não 401: a sessão é válida, só falta a permissão).
class Api::V1::Accounts::Crm::MetaAdsConnectionsController < Api::V1::Accounts::Crm::BaseController
  include DeferInteractiveAi

  # Tokens da Meta têm algumas centenas de caracteres; o teto barra corpos absurdos antes da Graph.
  MAX_TOKEN_LENGTH = 2048
  SELECTION_RESET = { ad_account_id: nil, ad_account_name: nil, ad_account_business_id: nil, ad_account_timezone: nil,
                      pixel_id: nil, pixel_name: nil, verified_at: nil }.freeze
  READ_ACTIONS = %w[show ad_accounts pixels funnels insights panel panel_ad panel_list].freeze

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

    error = ::Crm::MetaAds::TokenCheck.error_for(token)
    return render_unprocessable(error) if error

    save_connection!(token)
    Crm::MetaAds::BackfillJob.perform_later(Current.account.id)
    render json: payload
  end

  def facebook_login
    code = params[:code].to_s.strip
    return render_unprocessable('code_required') if code.blank?
    return render_unprocessable('code_too_long') if code.length > MAX_TOKEN_LENGTH
    return render_unprocessable('encryption_not_configured') unless Chatwoot.encryption_configured?

    token = ::Crm::MetaAds::FacebookLogin.new.exchange!(code)
    error = ::Crm::MetaAds::TokenCheck.error_for(token)
    return render_unprocessable(error) if error

    save_connection!(token, mode: 'facebook_login')
    Crm::MetaAds::BackfillJob.perform_later(Current.account.id)
    render json: payload
  rescue ::Crm::MetaAds::FacebookLogin::Error => e
    render_unprocessable(e.code)
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
    report = ::Crm::MetaAds::Panel::Report.new(connection, days: params[:days])
    render json: { panel: panel_payload(connection, report).merge(synced_at: connection.reload.insights_synced_at, refreshing: refreshing) }
  end

  def panel_ad
    connection = current_connection
    return render json: { ad: nil } if connection.blank? || connection.ad_account_id.blank?

    render json: { ad: ::Crm::MetaAds::Panel::AdDetail.new(connection, ad_id: params[:ad_id], days: params[:days]).payload }
  end

  def panel_list
    return render_unprocessable('invalid_step') unless ::Crm::MetaAds::Panel::PathList::STEPS.include?(params[:step])

    connection = current_connection
    return render json: { list: nil } if connection.blank? || connection.ad_account_id.blank?

    render json: { list: ::Crm::MetaAds::Panel::PathList.new(connection, step: params[:step], days: params[:days]).payload }
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

  # Colar um token novo (ou entrar com o Facebook) volta a conexão ao modo do token. No mesmo modo, a conta de
  # anúncios escolhida antes continua e a escolha seguinte confere se o novo token a enxerga. Trocar de modo
  # (#1069) limpa a escolha: o token novo não pode passar a ler a conta antiga sem a pessoa escolher de novo.
  def save_connection!(token, mode: 'token')
    connection = ::Crm::MetaAdsConnection.find_or_initialize_by(account_id: Current.account.id)
    connection.assign_attributes(SELECTION_RESET) if connection.persisted? && connection.mode != mode
    connection.update!(access_token: token, mode: mode, status: 'active', last_checked_at: Time.current, last_error: nil)
  end

  def setup
    @setup ||= ::Crm::MetaAds::Setup.new(Current.account)
  end

  def current_connection
    ::Crm::MetaAdsConnection.find_by(account_id: Current.account.id)
  end

  # O consultor recebe o Report da própria requisição: com 30 dias, os fatos dele reaproveitam a mesma coorte.
  # Pedido pelo token de API (o Guia) não marca as ações como mostradas: a métrica de aceite é do painel (D5.11).
  def panel_payload(connection, report)
    report.payload.merge(
      meta_comparison: ::Crm::MetaAds::Panel::MetaComparison.new(connection, report).payload,
      response_time: response_time(connection, report),
      advice: ::Crm::MetaAds::Advisor::Analysis.current(connection, locale: I18n.locale.to_s, report: report,
                                                                    shown: !authenticate_by_access_token?)
    )
  end

  # Sem conversa de anúncio no período não há o que medir. Com 30 dias é a mesma janela dos fatos do consultor
  # (§4.2): sai do cache deles, sem refazer a consulta sobre `messages` a cada GET.
  def response_time(connection, report)
    return if report.cohort.conversation_ads.empty?

    payload = if report.days == ::Crm::MetaAds::Advisor::Facts::COHORT_DAYS
                ::Crm::MetaAds::Advisor::Facts.new(connection, report: report).payload.dig(:account, :response)
              else
                ::Crm::MetaAds::Panel::ResponseTime.new(account_id: connection.account_id, range: report.range).payload
              end
    payload.merge(days: report.days)
  end

  def payload
    connection = current_connection
    ::Crm::MetaAdsConnection.public_payload_for(connection).merge(
      partner: ::Crm::MetaAds::Platform.public_payload,
      facebook_login: ::Crm::MetaAds::FacebookLogin.public_payload,
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
