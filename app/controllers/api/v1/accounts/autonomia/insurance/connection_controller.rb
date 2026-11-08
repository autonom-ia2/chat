class Api::V1::Accounts::Autonomia::Insurance::ConnectionController < Api::V1::Accounts::Autonomia::Insurance::BaseController
  # Quanto a requisição aguarda um login que OUTRO processo esteja fazendo (healthcheck, cotação). Abaixo
  # do Rack::Timeout de 15 s: passando disso a resposta volta com o estado do momento, e o login do outro
  # processo continua e grava a sessão.
  ESPERA_DO_LOGIN_NA_TELA = 10.seconds

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
    sincronizar!
    enqueue_scan! if connection.ready?
    render json: { payload: connection.public_payload }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # POST /connection/reconnect — nova autenticação com as credenciais guardadas.
  def reconnect
    return render_not_configured unless connection.persisted? && connection.credentials_present?

    sincronizar!
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

  # Login e status, sem varredura, com a espera curta da tela.
  def sincronizar!
    ::Autonomia::Insurance::Connections::Sync.new(connection, scan_capabilities: false, espera_do_login: ESPERA_DO_LOGIN_NA_TELA).call
  end

  # O estado de passagem é o que a tela acompanha até assentar. Se o job falhar, o próprio `ScanJob`
  # grava `degraded`; se ele nem rodar, o `HealthcheckJob#presas` re-sincroniza depois de 10 min.
  #
  # `discovering` SÓ para conexão pronta: ele é `usable?` quando já houve varredura, e as ferramentas
  # da Lia seguem usando a configuração anterior (chat#2647). Conexão fora do ar (credencial recusada,
  # portal caído, `degraded`) passa por `authenticating`, que não serve às ferramentas: sem isso, a
  # Lia tentaria login com uma senha que o portal já recusou antes do `ScanJob` confirmar qualquer coisa.
  def enqueue_scan!
    connection.update!(status: connection.ready? ? 'discovering' : 'authenticating')
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
