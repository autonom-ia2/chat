# Aba "WhatsApp API" de uma caixa WhatsApp Oficial (chat#1067). Só admin (update? da caixa).
# Respostas usam termos neutros: nada do motor externo vai para o painel.
class Api::V1::Accounts::WhatsappHybridConnectionsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_available
  before_action :fetch_connection, except: [:show, :create]

  def show
    connection = WhatsappHybrid::Connection.find_by(inbox_id: @inbox.id)
    return render json: payload(nil) if connection.nil?

    manager = WhatsappHybrid::SessionManager.new(connection)
    manager.refresh!
    manager.refresh_timelock!
    render json: payload(connection, qr_code: manager.qr)
  end

  def create
    manager = WhatsappHybrid::SessionManager.connect!(inbox: @inbox)
    render json: payload(manager.connection, qr_code: manager.qr)
  rescue Waha::Client::Error => e
    render_engine_error('connect_failed', e)
  end

  def update
    @connection.update!(settings_params.merge(risk_params))
    render json: payload(@connection)
  end

  def request_code
    code = WhatsappHybrid::SessionManager.new(@connection).pairing_code
    render json: { code: code }
  rescue Waha::Client::Error => e
    render_engine_error('code_failed', e)
  end

  def reconnect
    WhatsappHybrid::SessionManager.new(@connection).reconnect!
    render json: payload(@connection)
  rescue Waha::Client::Error => e
    render_engine_error('reconnect_failed', e)
  end

  # Pausar sem desvincular o aparelho (#1487): enquanto pausada, tudo sai pela oficial.
  def pause
    WhatsappHybrid::Pause.new(@connection).pause!
    render json: payload(@connection)
  rescue Waha::Client::Error => e
    render_engine_error('pause_failed', e)
  end

  # Retomar religa a mesma sessão, sem QR; se o WhatsApp tiver desvinculado o aparelho, a aba mostra o QR.
  def resume
    pause = WhatsappHybrid::Pause.new(@connection)
    pause.resume!
    render json: payload(@connection, qr_code: pause.qr)
  rescue Waha::Client::Error => e
    render_engine_error('resume_failed', e)
  end

  def destroy
    WhatsappHybrid::SessionManager.new(@connection).disconnect!
    head :no_content
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
  end

  def ensure_available
    return if WhatsappHybrid::Config.available_for?(@inbox)

    render json: { error: 'not_available' }, status: :not_found
  end

  def fetch_connection
    @connection = WhatsappHybrid::Connection.find_by!(inbox_id: @inbox.id)
  end

  def settings_params
    params.permit(:routing_enabled, :rate_limit_per_minute, disabled_origins: []).to_h
  end

  # O aceite de risco é auditado: quem, quando e de onde.
  def risk_params
    return {} unless params.key?(:risk_accepted)

    accepted = ActiveModel::Type::Boolean.new.cast(params[:risk_accepted])
    return { risk_accepted_at: nil, risk_accepted_by_id: nil, risk_accepted_ip: nil } unless accepted
    return {} if @connection.risk_accepted?

    { risk_accepted_at: Time.current, risk_accepted_by_id: current_user.id, risk_accepted_ip: request.remote_ip }
  end

  def payload(connection, qr_code: nil)
    return { available: true, connected: false, status: 'not_connected', same_number_inboxes: same_number_inboxes } if connection.nil?

    {
      available: true,
      **state_payload(connection),
      risk_accepted: connection.risk_accepted?,
      risk_accepted_at: connection.risk_accepted_at,
      routing_enabled: connection.routing_enabled,
      routing_active: connection.routable? && WhatsappHybrid::Config.routing_enabled?,
      disabled_origins: connection.disabled_origins,
      rate_limit_per_minute: connection.rate_limit_per_minute,
      campaign_rate_limit_per_minute: WhatsappHybrid::RateLimit::CAMPAIGN_PER_MINUTE,
      **limits_payload(connection),
      stats: { days: WhatsappHybrid::Stats::DAYS, by_origin: WhatsappHybrid::Stats.summary(connection) },
      same_number_inboxes: same_number_inboxes,
      qr: qr_code
    }
  end

  # Estado da sessão e do aparelho. Pausada (#1487) é decisão do administrador, não queda.
  def state_payload(connection)
    {
      status: connection.status,
      connected: connection.status == 'connected' && !connection.paused?,
      paused: connection.paused?,
      phone: connection.connected_phone,
      cloud_phone: connection.cloud_phone_digits,
      same_number: connection.same_number?
    }
  end

  # Outras caixas WhatsApp API comuns da conta no mesmo número (#1487): só aviso, nada é bloqueado.
  def same_number_inboxes
    WhatsappHybrid::SameNumberInboxes.new(account_id: @inbox.account_id, phone: @inbox.channel.phone_number).names
  end

  # O que o WhatsApp está limitando neste número: o ciclo de conversas novas e o limite temporário (chat#1480).
  def limits_payload(connection)
    { capping: capping_payload(connection), timelock: WhatsappHybrid::Timelock.new(connection).payload }
  end

  def capping_payload(connection)
    current = WhatsappHybrid::Capping.new(connection).current
    return { status: 'NONE' } if current.blank?

    { status: current['status'], used: current['used'], total: current['total'], cycle_end: current['cycle_end'] }
  end

  def render_engine_error(code, error)
    Rails.logger.error("[whatsapp_hybrid] #{code} inbox=#{@inbox.id}: #{error.message.to_s[0, 200]}")
    render json: { error: code }, status: :unprocessable_entity
  end
end
