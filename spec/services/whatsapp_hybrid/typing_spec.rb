require 'rails_helper'

describe WhatsappHybrid::Typing do
  let(:client) { instance_double(Waha::Client) }
  let(:typing) { described_class.new(client, session: 'hybrid-test', chat_id: '5511999990000@c.us') }
  let(:message) { build(:message, content: 'oi') }

  before { allow(Kernel).to receive(:sleep) }

  it 'shows typing, waits in proportion to the text and stops before sending' do
    allow(client).to receive_messages(start_typing: {}, stop_typing: {})
    long = build(:message, content: 'x' * 50)

    typing.simulate(long)

    expect(client).to have_received(:start_typing).with(session: 'hybrid-test', chat_id: '5511999990000@c.us').ordered
    expect(Kernel).to have_received(:sleep).with((long.outgoing_content.length * 0.04).clamp(1.0, 4.0)).ordered
    expect(client).to have_received(:stop_typing).ordered
  end

  it 'keeps the wait between one and four seconds' do
    expect(typing.duration_for(message)).to eq(1.0)
    expect(typing.duration_for(build(:message, content: 'x' * 1000))).to eq(4.0)
  end

  it 'still waits and lets the send go on when the engine refuses the typing indicator' do
    allow(client).to receive(:start_typing).and_raise(Waha::Client::Error, '404')
    allow(client).to receive(:stop_typing)

    expect { typing.simulate(message) }.not_to raise_error
    expect(Kernel).to have_received(:sleep)
    expect(client).not_to have_received(:stop_typing)
  end

  it 'can be turned off' do
    allow(client).to receive(:start_typing)

    with_modified_env(WHATSAPP_HYBRID_TYPING: 'false') { typing.simulate(message) }

    expect(client).not_to have_received(:start_typing)
    expect(Kernel).not_to have_received(:sleep)
  end
end
