class Api::V1::Accounts::Autonomia::Insurance::ConnectionController < Api::V1::Accounts::Autonomia::Insurance::BaseController
  # GET /connection — estado atual (sem credenciais).
  def show
    render json: { payload: connection.persisted? ? connection.public_payload : blank_payload }
  end

  # POST /connection — grava credenciais (cifradas) e sincroniza com o portal.
  # A senha entra por aqui uma única vez e nunca volta em resposta nenhuma.
  def create
    connection.assign_attributes(credential_params)
    connection.save!
    ::Autonomia::Insurance::Connections::Sync.new(connection).call
    render json: { payload: connection.public_payload }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # POST /connection/reconnect — nova autenticação com as credenciais guardadas.
  def reconnect
    return render_not_configured unless connection.persisted? && connection.credentials_present?

    ::Autonomia::Insurance::Connections::Sync.new(connection, scan_capabilities: false).call
    render json: { payload: connection.public_payload }
  end

  # POST /connection/scan — reautentica e refaz a descoberta de produtos/seguradoras.
  def scan
    return render_not_configured unless connection.persisted? && connection.credentials_present?

    ::Autonomia::Insurance::Connections::Sync.new(connection).call
    render json: { payload: connection.public_payload }
  end

  # DELETE /connection — apaga credenciais e estado da conexão desta conta.
  def destroy
    connection.destroy! if connection.persisted?
    render json: { payload: blank_payload }
  end

  private

  def credential_params
    params.require(:connection).permit(:username, :password)
  end

  def blank_payload
    { provider: provider_param, status: 'not_configured', capabilities: {},
      encryption_available: ::Autonomia::Insurance::Connection.encryption_available? }
  end

  def render_not_configured
    render json: { error: 'autonomia.insurance.connection.not_configured' }, status: :unprocessable_entity
  end
end
