require 'rails_helper'

# chat#1486: depois de um 463, o retrato do limite é atualizado fora do envio.
describe WhatsappHybrid::TimelockRefreshJob do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Waha::Client) }
  let(:ends_at) { 6.hours.from_now.to_i }
  let!(:connection) do
    WhatsappHybrid::Connection.create!(
      account: inbox.account, inbox: inbox, session_name: 'hybrid-test', status: 'connected',
      connected_phone: channel.phone_number.delete('^0-9'), risk_accepted_at: Time.current, status_checked_at: Time.current
    )
  end
  let(:timelock) { WhatsappHybrid::Timelock.new(connection) }

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    Redis::Alfred.delete(timelock.key)
  end

  it 'runs on the default queue, not on the high queue of the send' do
    expect { described_class.perform_later(connection.id) }.to have_enqueued_job.on_queue('default')
  end

  it 'asks the engine even when the snapshot is fresh and saves the limit' do
    timelock.apply!('isActive' => false)
    allow(client).to receive(:timelock).and_return({ 'isActive' => true, 'timeEnforcementEnds' => ends_at })

    described_class.perform_now(connection.id)

    expect(client).to have_received(:timelock).with('hybrid-test').once
    expect(timelock.payload).to eq(active: true, ends_at: ends_at)
  end

  it 'survives a failure of the engine, keeping the last snapshot' do
    timelock.apply!('isActive' => true, 'timeEnforcementEnds' => ends_at)
    allow(client).to receive(:timelock).and_raise(Waha::Client::Timeout, 'sem resposta')

    expect { described_class.perform_now(connection.id) }.not_to raise_error

    expect(timelock.payload).to eq(active: true, ends_at: ends_at)
    expect(timelock).to be_fresh
  end

  it 'does nothing when the connection no longer exists' do
    allow(client).to receive(:timelock)

    described_class.perform_now(0)

    expect(client).not_to have_received(:timelock)
  end
end
