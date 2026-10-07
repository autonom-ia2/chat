require 'rails_helper'

RSpec.describe WhatsappHybrid::TeardownSessionJob do
  let(:client) { instance_double(Waha::Client) }

  before { allow(Waha::Client).to receive(:new).and_return(client) }

  it 'logs out and deletes the session' do
    allow(client).to receive(:logout_session)
    allow(client).to receive(:delete_session)

    described_class.perform_now('hybrid-1')

    expect(client).to have_received(:delete_session).with('hybrid-1')
  end

  it 'still deletes when logout fails' do
    allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'boom')
    allow(client).to receive(:delete_session)

    described_class.perform_now('hybrid-1')

    expect(client).to have_received(:delete_session).with('hybrid-1')
  end

  it 'treats a session the engine no longer has as done' do
    allow(client).to receive(:logout_session).and_raise(Waha::Client::NotFound, '404')
    allow(client).to receive(:delete_session).and_raise(Waha::Client::NotFound, '404')

    expect { described_class.perform_now('hybrid-1') }.not_to have_enqueued_job(described_class)
  end

  it 'tries again later when the engine is down' do
    allow(client).to receive(:logout_session).and_raise(Waha::Client::Error, 'down')
    allow(client).to receive(:delete_session).and_raise(Waha::Client::Error, 'WAHA DELETE -> 502')

    expect { described_class.perform_now('hybrid-1') }.to have_enqueued_job(described_class).with('hybrid-1')
  end
end
