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
  it 'keeps the reason when the portal answers with a degraded status' do
    # Arrange
    connector = instance_double(Autonomia::Insurance::Connector::Mock)
    allow(connector).to receive(:connection_status)
      .and_return({ 'status' => 'degraded', 'reason' => 'protocol: unexpected login payload' })

    # Act
    result = described_class.new(connection, connector: connector).call

    # Assert
    expect(result.status).to eq('degraded')
    expect(result.last_error).to include('unexpected login payload')
    expect(result.last_capability_scan_at).to be_nil # não descobre capacidades de conexão ruim
  end

  it 'records something even when the adapter sends no reason' do
    # Arrange — adapter antigo, sem o campo. "status degraded" ainda é pista; vazio não é.
    connector = instance_double(Autonomia::Insurance::Connector::Mock)
    allow(connector).to receive(:connection_status).and_return({ 'status' => 'degraded' })

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
end
