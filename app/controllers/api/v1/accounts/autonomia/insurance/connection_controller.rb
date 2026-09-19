class Api::V1::Accounts::Autonomia::Insurance::ConnectionController < Api::V1::Accounts::Autonomia::Insurance::BaseController
  # GET /connection — estado atual (sem credenciais).
  def show
    render json: { payload: connection.persisted? ? connection.public_payload : blank_payload }
  end

  # POST /connection — grava credenciais (cifradas) e sincroniza com o portal.
  # A senha entra por aqui uma única vez e nunca volta em resposta nenhuma.
  #
  # Dentro da requisição, só o login e o status. A descoberta de capacidades vai para o `ScanJob`,
  # como no `#scan`: rodando aqui, ela estourava o Rack::Timeout de 15 s (500 duas vezes na conta 16
  # em 19/09/2026) e deixava a conexão em `discovering`, sem capacidades (#469).
  def create
    connection.assign_attributes(credential_params)
    connection.save!
    ::Autonomia::Insurance::Connections::Sync.new(connection, scan_capabilities: false).call
    enqueue_scan! if connection.ready?
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
  # A descoberta leva perto de 25 s e o proxy corta antes. Rodando aqui dentro, o corretor recebia
  # 500 e a conexão ficava parada em `discovering`, com os botões da tela desabilitados. Agora ela
  # sai como trabalho de fundo: a resposta volta na hora com o estado transitório, e a tela
  # acompanha até assentar.
  def scan
    return render_not_configured unless connection.persisted? && connection.credentials_present?

    enqueue_scan!
    render json: { payload: connection.public_payload }, status: :accepted
  end

  # DELETE /connection — apaga credenciais e estado da conexão desta conta.
  def destroy
    connection.destroy! if connection.persisted?
    render json: { payload: blank_payload }
  end

  private

  # `discovering` é o estado que a tela acompanha até assentar. Se o job falhar, o próprio `ScanJob`
  # grava `degraded`; se ele nem rodar, o `HealthcheckJob#presas` re-sincroniza depois de 10 min.
  def enqueue_scan!
    connection.update!(status: 'discovering')
    ::Autonomia::Insurance::Connections::ScanJob.perform_later(connection.id)
  end

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
