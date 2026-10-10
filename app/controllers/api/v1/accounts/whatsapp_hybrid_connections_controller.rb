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
    return { available: true, connected: false, status: 'not_connected' } if connection.nil?

    {
      available: true,
      status: connection.status,
      connected: connection.status == 'connected',
      phone: connection.connected_phone,
      cloud_phone: connection.cloud_phone_digits,
      same_number: connection.same_number?,
      risk_accepted: connection.risk_accepted?,
      risk_accepted_at: connection.risk_accepted_at,
      routing_enabled: connection.routing_enabled,
      routing_active: connection.routable? && WhatsappHybrid::Config.routing_enabled?,
      disabled_origins: connection.disabled_origins,
      rate_limit_per_minute: connection.rate_limit_per_minute,
      campaign_rate_limit_per_minute: WhatsappHybrid::RateLimit::CAMPAIGN_PER_MINUTE,
      capping: capping_payload(connection),
      stats: { days: WhatsappHybrid::Stats::DAYS, by_origin: WhatsappHybrid::Stats.summary(connection) },
      qr: qr_code
    }
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
