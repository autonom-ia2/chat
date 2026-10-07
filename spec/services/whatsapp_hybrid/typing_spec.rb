require 'rails_helper'

describe WhatsappHybrid::Typing do
  let(:client) { instance_double(Waha::Client) }
  let(:conversation) { create(:conversation) }
  let(:sleeps) { [] }
  let(:typing) { described_class.new(client, session: 'hybrid-test', chat_id: '5511999990000@c.us', rng: Random.new(42)) }

  def outgoing(content)
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                     message_type: :outgoing, content: content)
  end

  before { allow(Kernel).to receive(:sleep) { |seconds| sleeps << seconds } }

  it 'reads first, then shows typing for a human time, then stops before sending' do
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                     message_type: :incoming, content: 'x' * 60)
    allow(client).to receive_messages(start_typing: {}, stop_typing: {})
    message = outgoing('Já tenho o retorno para você, posso te ligar agora?')

    typing.simulate(message)

    expect(sleeps.first).to eq(2.0)
    expect(sleeps.last).to be_between(52 / 6.5, 52 / 4.5)
    expect(client).to have_received(:start_typing).with(session: 'hybrid-test', chat_id: '5511999990000@c.us')
    expect(client).to have_received(:stop_typing)
  end

  it 'types at a human speed that changes from message to message' do
    message = outgoing('x' * 30)
    times = Array.new(5) { typing.typing_for(message) }

    expect(times).to all(be_between(30 / 6.5, 30 / 4.5))
    expect(times.uniq.size).to be > 1
  end

  it 'keeps typing between one and nine seconds' do
    expect(typing.typing_for(outgoing('oi'))).to eq(1.0)
    expect(typing.typing_for(outgoing('x' * 2000))).to eq(9.0)
  end

  it 'reads for at least half a second even without a customer message' do
    expect(typing.reading_for(outgoing('oi'))).to eq(0.5)
  end

  it 'still lets the send go on when the engine refuses the typing indicator' do
    allow(client).to receive(:start_typing).and_raise(Waha::Client::Error, '404')
    allow(client).to receive(:stop_typing)

    expect { typing.simulate(outgoing('oi')) }.not_to raise_error
    expect(client).not_to have_received(:stop_typing)
  end

  it 'can be turned off' do
    allow(client).to receive(:start_typing)

    with_modified_env(WHATSAPP_HYBRID_TYPING: 'FALSE') { typing.simulate(outgoing('oi')) }

    expect(client).not_to have_received(:start_typing)
    expect(sleeps).to be_empty
  end
end
