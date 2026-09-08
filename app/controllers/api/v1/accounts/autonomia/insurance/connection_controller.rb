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
  # A descoberta leva perto de 25 s e o proxy corta antes. Rodando aqui dentro, o corretor recebia
  # 500 e a conexão ficava parada em `discovering`, com os botões da tela desabilitados. Agora ela
  # sai como trabalho de fundo: a resposta volta na hora com o estado transitório, e a tela
  # acompanha até assentar.
  def scan
    return render_not_configured unless connection.persisted? && connection.credentials_present?

    connection.update!(status: 'discovering')
    ::Autonomia::Insurance::Connections::ScanJob.perform_later(connection.id)
    render json: { payload: connection.public_payload }, status: :accepted
  end

  # POST /connection/portal_link — a URL que abre o AGGER já autenticado, para o corretor cotar ao
  # lado do agente sem derrubar a sessão dele (medido em 07/09/2026: não derruba).
  #
  # A CREDENCIAL SAI DAQUI PARA O ADAPTER, e esta é a segunda rota a fazer isso — a primeira é o
  # `create`. Não há alternativa: o link É um login cifrado, e quem sabe montar a cifra é o adapter,
  # que é stateless e não guarda senha nenhuma. Ela é lida pelo `encrypts` do Rails, vai na chamada,
  # e nada disso é gravado.
  #
  # A RESPOSTA TAMBÉM É A CREDENCIAL, agora cifrada. Por isso ela não entra em log, telemetria nem
  # banco: o corretor recebe a URL, o navegador abre, e ela morre ali. Gerar no clique — nunca
  # antes, nunca em lote — é o que mantém essa frase verdadeira.
  def portal_link
    return render_not_configured unless connection.persisted? && connection.credentials_present?

    alvo = connection.last_quote
    # Sem cotação não há para onde apontar: a rota de handoff do portal abre UMA cotação, e não a
    # home. Acontece em conta recém-conectada, e a tela usa este erro para explicar em vez de abrir
    # uma aba quebrada.
    return render_sem_cotacao if alvo.blank?

    payload = ::Autonomia::Insurance::Connector.client.portal_link(
      provider: connection.provider,
      username: connection.username, password: connection.password,
      quote_id: alvo['quote_id'], branch: alvo['branch'] || 'auto', version: alvo['version'] || 1
    )
    render json: { payload: { url: payload['url'] } }
  rescue ::Autonomia::Insurance::Connector::Error => e
    # O `kind` decide o status, como no resto do módulo: credencial recusada é 401 e o resto é
    # falha de integração. A MENSAGEM do portal não sai daqui — ela já carregou dado de segurado
    # antes, e a tela tem texto próprio por estado.
    render json: { error: "autonomia.insurance.connection.portal_link.#{e.kind}" },
           status: e.kind == :auth_required ? :unauthorized : :bad_gateway
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

  def render_sem_cotacao
    render json: { error: 'autonomia.insurance.connection.no_quote_yet' }, status: :unprocessable_entity
  end
end
