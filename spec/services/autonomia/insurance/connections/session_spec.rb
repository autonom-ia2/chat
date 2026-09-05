require 'rails_helper'

# O portal aceita UMA sessão viva por login: abrir outra invalida a anterior. Estes testes travam o
# contrato que faz várias cotações da mesma corretora conviverem — e que impede o healthcheck da
# tela de Conexões de encerrar a sessão de uma cotação em andamento.
RSpec.describe Autonomia::Insurance::Connections::Session do
  let(:account) { create(:account) }

  before { enable_test_encryption! }

  def connection
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
  end

  # Connector que CONTA quantas vezes abriu sessão. É o número que importa: cada login a mais é uma
  # sessão a menos para quem estava usando a anterior.
  def counting_connector(expires_in: 3.hours)
    Class.new(Autonomia::Insurance::Connector::Client) do
      attr_reader :logins

      define_method(:initialize) do
        super()
        @logins = 0
        @expires_in = expires_in
      end

      define_method(:open_session) do |**|
        @logins += 1
        { 'platform' => 'agger', 'data' => { 'multicalculoToken' => "token-#{@logins}" },
          'expires_at' => @expires_in.from_now.utc.iso8601, 'account_label' => 'CORRETORA X' }
      end
    end.new
  end

  it 'opens the session once and hands the same one to every caller' do
    # Arrange
    record = connection
    connector = counting_connector

    # Act — três consumidores diferentes pedindo a sessão da mesma conexão
    first = described_class.new(record, connector: connector).resolve!
    second = described_class.new(record.reload, connector: connector).resolve!
    third = described_class.new(record.reload, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(1)
    expect(first).to eq(second).and eq(third)
    expect(record.reload.session_expires_at).to be_present
    expect(record.external_account_label).to eq('CORRETORA X')
  end

  it 'stores the session encrypted, never in plain text' do
    # Arrange
    record = connection

    # Act
    described_class.new(record, connector: counting_connector).resolve!

    # Assert — o valor cru na coluna não pode conter o token
    raw = Autonomia::Insurance::Connection.connection.select_value(
      "SELECT session_payload FROM autonomia_insurance_connections WHERE id = #{record.id}"
    )
    expect(record.reload.session['multicalculoToken']).to eq('token-1')
    expect(raw).not_to include('token-1')
  end

  it 'opens a single session when two quotes start at the same time' do
    # Arrange — duas execuções concorrentes sobre a mesma linha
    record = connection
    connector = counting_connector
    other = Autonomia::Insurance::Connection.find(record.id)

    # Act — o recheck DENTRO do lock é o que evita o segundo login
    described_class.new(record, connector: connector).resolve!
    described_class.new(other, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(1)
  end

  it 'opens a new session when the stored one is about to expire' do
    # Arrange — dentro da margem: renovar cedo evita a sessão morrer no meio de um polling
    record = connection
    connector = counting_connector(expires_in: 1.minute)

    # Act
    described_class.new(record, connector: connector).resolve!
    described_class.new(record.reload, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(2)
  end

  it 'never reuses a session the portal did not put a deadline on' do
    # Arrange — sem prazo não dá para saber se ainda vale; um login a mais é melhor do que uma
    # cotação que morre no meio
    record = connection
    connector = Class.new(Autonomia::Insurance::Connector::Client) do
      attr_reader :logins

      def initialize
        super
        @logins = 0
      end

      def open_session(**)
        @logins += 1
        { 'platform' => 'agger', 'data' => { 'token' => 'x' } }
      end
    end.new

    # Act
    described_class.new(record, connector: connector).resolve!
    described_class.new(record.reload, connector: connector).resolve!

    # Assert
    expect(connector.logins).to eq(2)
  end

  it 'renews by forgetting the stored session first' do
    # Arrange
    record = connection
    connector = counting_connector

    # Act — é o caminho de "o portal recusou o que guardamos"
    described_class.new(record, connector: connector).resolve!
    renewed = described_class.new(record.reload, connector: connector).renew!

    # Assert
    expect(connector.logins).to eq(2)
    expect(renewed['multicalculoToken']).to eq('token-2')
    expect(record.reload.session['multicalculoToken']).to eq('token-2')
  end

  it 'refuses to open a session without credentials' do
    # Arrange
    empty = Autonomia::Insurance::Connection.create!(account: account)

    # Act / Assert
    expect { described_class.new(empty, connector: counting_connector).resolve! }
      .to raise_error(an_object_having_attributes(kind: :validation))
  end

  it 'treats a malformed session payload as a protocol error instead of storing garbage' do
    # Arrange
    record = connection
    broken = Class.new(Autonomia::Insurance::Connector::Client) do
      def open_session(**) = { 'platform' => 'agger' }
    end.new

    # Act / Assert
    expect { described_class.new(record, connector: broken).resolve! }
      .to raise_error(an_object_having_attributes(kind: :protocol))
    expect(record.reload.session).to be_nil
  end
end
