require 'rails_helper'

RSpec.describe Autonomia::Insurance::Connections::Sync do
  let(:account) { create(:account) }

  before { enable_test_encryption! }

  def connection(password: 'segredo')
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: password)
  end

  it 'authenticates, scans capabilities and marks the connection ready' do
    result = described_class.new(connection, connector: Autonomia::Insurance::Connector::Mock.new).call

    expect(result.status).to eq('ready')
    expect(result.external_account_label).to be_present
    expect(result.capabilities['products'].size).to eq(3)
    expect(result.last_capability_scan_at).to be_present
    expect(result.last_error).to be_nil
  end

  # Aconteceu em produção em 04/09/2026: o connector devolveu um payload VÁLIDO dizendo `degraded`,
  # o código tratou como sucesso e zerou `last_error`. A tela mostrou "conectado com alertas" sem
  # dizer qual alerta, o banco não guardou nada, e não houve como diagnosticar depois.
  # Payload bem-formado com status ruim NÃO é sucesso.
  # O `Sync` abre (ou reusa) a sessão ANTES de perguntar o status — mudou na #331. Um double que só
  # conhece `connection_status` estoura em `open_session`, então o helper cobre as duas pontas.
  def connector_answering(status_payload)
    instance_double(Autonomia::Insurance::Connector::Mock,
                    open_session: { 'platform' => 'agger', 'data' => { 'token' => 'x' },
                                    'expires_at' => 3.hours.from_now.utc.iso8601 },
                    connection_status: status_payload)
  end

  it 'keeps the reason when the portal answers with a degraded status' do
    # Arrange
    connector = connector_answering({ 'status' => 'degraded',
                                      'reason' => 'protocol: unexpected login payload' })

    # Act
    result = described_class.new(connection, connector: connector).call

    # Assert
    expect(result.status).to eq('degraded')
    expect(result.last_error).to include('unexpected login payload')
    expect(result.last_capability_scan_at).to be_nil # não descobre capacidades de conexão ruim
  end

  it 'records something even when the adapter sends no reason' do
    # Arrange — adapter antigo, sem o campo. "status degraded" ainda é pista; vazio não é.
    connector = connector_answering({ 'status' => 'degraded' })

    # Act / Assert
    expect(described_class.new(connection, connector: connector).call.last_error).to include('degraded')
  end

  it 'clears the reason once the connection is healthy again' do
    # Arrange — conexão que já falhou antes; o erro velho não pode ficar na tela para sempre
    stale = connection
    stale.update!(last_error: 'protocol: erro antigo')

    # Act
    result = described_class.new(stale, connector: Autonomia::Insurance::Connector::Mock.new).call

    # Assert
    expect(result.status).to eq('ready')
    expect(result.last_error).to be_nil
  end

  it 'translates connector errors into status + last_error without raising' do
    result = described_class.new(connection(password: 'invalid'), connector: Autonomia::Insurance::Connector::Mock.new).call

    expect(result.status).to eq('auth_required')
    expect(result.last_error).to include('auth_required')
    expect(result.capabilities).to eq({})
  end

  it 'maps unavailable/timeout to offline and protocol to degraded' do
    stub = Class.new(Autonomia::Insurance::Connector::Client) do
      def initialize(kind)
        super()
        @kind = kind
      end

      def open_session(**) = raise(Autonomia::Insurance::Connector::Error.new(@kind, 'boom'))
    end
    record = connection
    expect(described_class.new(record, connector: stub.new(:timeout)).call.status).to eq('offline')
    expect(described_class.new(record, connector: stub.new(:protocol)).call.status).to eq('degraded')
  end

  it 'never raises: unknown status, non-hash payload and unexpected errors all become degraded' do
    weird = Class.new(Autonomia::Insurance::Connector::Client) do
      def initialize(payload)
        super()
        @payload = payload
      end

      # A sessão abre normalmente; o payload esquisito vem do status, que é onde o Sync valida.
      def open_session(**)
        { 'platform' => 'agger', 'data' => { 'token' => 'x' }, 'expires_at' => 3.hours.from_now.utc.iso8601 }
      end

      def connection_status(**)
        raise 'boom' if @payload == :raise

        @payload
      end
    end
    record = connection

    expect(described_class.new(record, connector: weird.new({ 'status' => 'weird' })).call.status).to eq('degraded')
    expect(record.last_error).to include('unknown status')
    expect(described_class.new(record, connector: weird.new('nope')).call.status).to eq('degraded')
    expect(described_class.new(record, connector: weird.new(:raise)).call.status).to eq('degraded')
    expect(record.last_error).to eq('unexpected: RuntimeError')
  end

  it 'keeps e-mails and tokens out of last_error' do
    leaky = Class.new(Autonomia::Insurance::Connector::Client) do
      def open_session(**)
        raise Autonomia::Insurance::Connector::Error.new(
          :auth_required,
          'auth failed for corretora@exemplo.com.br token eyJhbGciOiJIUzI1NiJ9abcdefghijklmnopqrstuvwxyz'
        )
      end
    end

    result = described_class.new(connection, connector: leaky.new).call

    expect(result.status).to eq('auth_required')
    expect(result.last_error).to start_with('auth_required')
    expect(result.last_error).not_to include('corretora@exemplo.com.br')
    expect(result.last_error).not_to include('eyJ')
  end

  it 'skips the connector entirely without credentials' do
    empty = Autonomia::Insurance::Connection.create!(account: account)
    expect(described_class.new(empty, connector: nil).call.status).to eq('not_configured')
  end

  # CRITÉRIO 1.1 — a falha que não é do corretor não vira pedido de senha.
  #
  # O caminho que faltava: sessão perdida chega como PAYLOAD DE SUCESSO (HTTP 200 com o motivo
  # dentro), e não como exceção. O `with_fresh_session` só reage a exceção, então este caso passava
  # direto e gravava `auth_required` — o estado que a tela traduz em "confira o usuário e a senha".
  # Em 05/09/2026 isso custou duas trocas de senha que estavam corretas.
  describe 'sessão perdida (1.1)' do
    def connector_que_perde_a_sessao(depois:)
      respostas = [
        { 'status' => 'degraded',
          'failure' => { 'cause' => 'session_lost', 'actor' => 'nobody', 'retryable' => true },
          'reason' => 'session_lost: GET /cfg/corretora -> 403' },
        depois
      ]
      instance_double(Autonomia::Insurance::Connector::Mock,
                      open_session: { 'platform' => 'agger', 'data' => { 'token' => 'x' },
                                      'expires_at' => 3.hours.from_now.utc.iso8601 },
                      capabilities: { 'products' => [], 'scanned_at' => Time.current.iso8601 })
        .tap { |dobro| allow(dobro).to receive(:connection_status) { respostas.shift } }
    end

    it 'renova a sessão e usa o resultado da segunda tentativa' do
      # Arrange
      connector = connector_que_perde_a_sessao(
        depois: { 'status' => 'ready', 'account_label' => 'CORRETORA X' }
      )

      # Act
      result = described_class.new(connection, connector: connector, scan_capabilities: false).call

      # Assert
      expect(result.status).to eq('ready')
      expect(result.last_error).to be_nil
    end

    it 'nunca grava auth_required por causa de sessão perdida' do
      # Arrange — a segunda tentativa também não vai bem, mas ainda assim não é culpa da credencial
      connector = connector_que_perde_a_sessao(
        depois: { 'status' => 'degraded',
                  'failure' => { 'cause' => 'session_lost', 'actor' => 'nobody' },
                  'reason' => 'session_lost: de novo' }
      )

      # Act
      result = described_class.new(connection, connector: connector, scan_capabilities: false).call

      # Assert
      expect(result.status).not_to eq('auth_required')
      expect(result.last_failure['actor']).to eq('nobody')
    end

    it 'tenta UMA vez: insistir só multiplica login no portal' do
      # Arrange
      connector = connector_que_perde_a_sessao(
        depois: { 'status' => 'degraded', 'failure' => { 'cause' => 'session_lost', 'actor' => 'nobody' } }
      )

      # Act
      described_class.new(connection, connector: connector, scan_capabilities: false).call

      # Assert
      expect(connector).to have_received(:connection_status).twice
    end
  end

  # CRITÉRIOS 1.2 e 1.6 — o diagnóstico estruturado sobrevive até a tela.
  describe 'diagnóstico gravado' do
    it 'guarda camadas e evidência, e limpa a falha quando volta a ficar boa' do
      # Arrange
      camadas = { 'runtime' => 'ok', 'platform_auth' => 'ok', 'insurer_auth' => 'unknown',
                  'product_support' => 'unknown', 'risk' => 'unknown' }
      evidencia = { 'check' => 'session_probe', 'at' => '2026-09-05T17:02:00.000Z',
                    'outcome' => 'ok', 'detail' => 'GET /cfg/corretora' }
      connector = connector_answering({ 'status' => 'ready', 'account_label' => 'CORRETORA X',
                                        'layers' => camadas, 'evidence' => evidencia })

      # Act
      result = described_class.new(connection, connector: connector, scan_capabilities: false).call

      # Assert
      expect(result.layers).to eq(camadas)
      expect(result.last_evidence['detail']).to eq('GET /cfg/corretora')
      expect(result.last_failure).to be_nil
    end

    it 'não apaga o resto de metadata ao gravar o diagnóstico' do
      # Arrange — a comissão da corretora mora no mesmo jsonb
      conexao = connection
      conexao.update!(metadata: { 'commission_percent' => 12.5 })
      connector = connector_answering({ 'status' => 'ready', 'account_label' => 'X',
                                        'layers' => { 'runtime' => 'ok' } })

      # Act
      described_class.new(conexao, connector: connector, scan_capabilities: false).call

      # Assert
      expect(conexao.reload.metadata['commission_percent']).to eq(12.5)
    end
  end

  # Achados do revisor em 05/09/2026. Os tres sao regressoes possiveis, nao hipoteses.
  describe 'escrita concorrente e redacao' do
    it 'nao apaga o que o polling de cotacao acabou de gravar no mesmo metadata' do
      # Arrange — a conexao ja tem sessao VIVA. Sem isso o Sync abre uma sob `with_lock`, e esse
      # lock recarrega a linha por tabela, mascarando a corrida que este exemplo existe para pegar.
      conexao = connection
      conexao.store_session!({ 'token' => 'x' }, expires_at: 3.hours.from_now)
      conexao.update!(metadata: { 'commission_percent' => 12.5 })
      velha = Autonomia::Insurance::Connection.find(conexao.id) # retrato de antes
      connector = connector_answering({ 'status' => 'ready', 'account_label' => 'X',
                                        'layers' => { 'runtime' => 'ok' } })

      # Act — a cotacao registra a pendencia; so entao o healthcheck, que carregou antes, termina
      conexao.record_insurers_pending_auth!(['5'], nomes: ['Allianz'])
      described_class.new(velha, connector: connector, scan_capabilities: false).call

      # Assert
      recarregada = conexao.reload
      expect(recarregada.insurers_pending_auth&.dig('codes')).to eq(['5'])
      expect(recarregada.layers).to eq({ 'runtime' => 'ok' })
      expect(recarregada.metadata['commission_percent']).to eq(12.5)
    end

    it 'redige e-mail e token tambem nos campos estruturados, e nao so no last_error' do
      # Arrange — o adapter ja redige, mas a regua nao pode depender disso: e a mesma resposta que
      # motivou o `sanitize` do `last_error`, e vai para a mesma tela.
      connector = connector_answering(
        { 'status' => 'degraded',
          'failure' => { 'cause' => 'integration_outdated',
                         'detalhe' => 'recusado para corretora@exemplo.com.br' },
          'evidence' => { 'check' => 'login', 'outcome' => 'failed',
                          'detail' => 'token abcdefghijklmnopqrstuvwxyz0123456789' } }
      )

      # Act
      result = described_class.new(connection, connector: connector, scan_capabilities: false).call

      # Assert
      expect(result.last_failure.to_s).not_to include('corretora@exemplo.com.br')
      expect(result.last_evidence.to_s).not_to include('abcdefghijklmnopqrstuvwxyz0123456789')
      expect(result.last_evidence['check']).to eq('login')
    end
  end

  # Achado da segunda revisao. Status e diagnostico gravados em transacoes separadas abrem uma
  # janela em que a tela le `ready` com o `failure` anterior — e e o `failure` que decide se ela
  # pede a senha de volta. Seria a mesma contradicao do incidente: conectado e "confira sua senha"
  # lado a lado.
  #
  # A janela nao da para observar de fora sem thread; o que da para afirmar e o invariante que a
  # fecha: `apply_status!` grava a linha UMA vez.
  it 'grava status e diagnostico numa transacao so' do
    # Arrange
    conexao = connection
    conexao.store_session!({ 'token' => 'x' }, expires_at: 3.hours.from_now)
    conexao.merge_metadata!('last_failure' => { 'cause' => 'session_lost', 'actor' => 'nobody' })
    connector = connector_answering({ 'status' => 'ready', 'account_label' => 'X',
                                      'layers' => { 'runtime' => 'ok' } })
    updates = 0
    assinatura = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, dados|
      sql = dados[:sql].to_s
      updates += 1 if sql.start_with?('UPDATE') && sql.include?('autonomia_insurance_connections')
    end

    # Act
    described_class.new(conexao, connector: connector, scan_capabilities: false).call

    # Assert — `mark!(authenticating)` e uma; `apply_status!` tem que ser a outra, e so
    ActiveSupport::Notifications.unsubscribe(assinatura)
    expect(updates).to eq(2)
    expect(conexao.reload.status).to eq('ready')
    expect(conexao.last_failure).to be_nil
  end
end
