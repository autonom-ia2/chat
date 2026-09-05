require 'rails_helper'

# O ping periódico existe porque "Última verificação" só mudava quando alguém clicava num botão — o
# corretor via "Autenticada" durante horas enquanto a conexão já estava morta.
RSpec.describe Autonomia::Insurance::Connections::HealthcheckJob, type: :job do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }

  before { enable_test_encryption! }

  around do |example|
    with_modified_env INSURANCE_QUOTING_ENABLED: 'true' do
      example.run
    end
  end

  def connection(status:, account_record: account)
    record = Autonomia::Insurance::Connection.create!(account: account_record, username: 'c@x.com',
                                                      password: 'segredo')
    record.update!(status: status, last_healthcheck_at: 3.hours.ago)
    record
  end

  it 'pings a ready connection and refreshes the check timestamp' do
    # Arrange
    record = connection(status: 'ready')

    # Act
    described_class.new.perform

    # Assert
    expect(record.reload.last_healthcheck_at).to be_within(30.seconds).of(Time.current)
    expect(record.status).to eq('ready')
  end

  it 'never rediscovers products: that is the heavy scan and stays manual' do
    # Arrange
    record = connection(status: 'ready')

    # Act
    described_class.new.perform

    # Assert — o ping é barato de propósito
    expect(record.reload.capabilities).to eq({})
    expect(record.last_capability_scan_at).to be_nil
  end

  it 'leaves auth_required alone, so a refused credential is not retried every 30 minutes' do
    # Arrange — insistir com credencial recusada é o caminho para bloquear a conta da corretora
    record = connection(status: 'auth_required')
    checked_at = record.last_healthcheck_at

    # Act
    described_class.new.perform

    # Assert
    expect(record.reload.last_healthcheck_at).to be_within(1.second).of(checked_at)
  end

  it 'skips accounts with the module turned off' do
    # Arrange
    other = create(:account)
    record = connection(status: 'ready', account_record: other)
    checked_at = record.last_healthcheck_at

    # Act
    described_class.new.perform

    # Assert
    expect(record.reload.last_healthcheck_at).to be_within(1.second).of(checked_at)
  end

  it 'keeps checking the other connections when one blows up' do
    # Arrange
    broken = connection(status: 'ready')
    other_account = create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true })
    healthy = connection(status: 'ready', account_record: other_account)
    allow(Autonomia::Insurance::Connections::Sync).to receive(:new).and_call_original
    allow(Autonomia::Insurance::Connections::Sync).to receive(:new)
      .with(having_attributes(id: broken.id), any_args).and_raise('boom')

    # Act / Assert
    expect { described_class.new.perform }.not_to raise_error
    expect(healthy.reload.last_healthcheck_at).to be_within(30.seconds).of(Time.current)
  end
end
