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

      def connection_status(**) = raise(Autonomia::Insurance::Connector::Error.new(@kind, 'boom'))
    end
    record = connection
    expect(described_class.new(record, connector: stub.new(:timeout)).call.status).to eq('offline')
    expect(described_class.new(record, connector: stub.new(:protocol)).call.status).to eq('degraded')
  end

  it 'skips the connector entirely without credentials' do
    empty = Autonomia::Insurance::Connection.create!(account: account)
    expect(described_class.new(empty, connector: nil).call.status).to eq('not_configured')
  end
end
