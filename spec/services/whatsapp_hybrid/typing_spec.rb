require 'rails_helper'

# Números do Humanize v3 (google-saas/lib/services/automation/humanize/config.ts).
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

  it 'shows typing for the human time and stops before sending' do
    allow(client).to receive_messages(start_typing: {}, stop_typing: {})

    typing.simulate(outgoing('Já tenho o retorno para você, posso te ligar agora?'))

    expect(client).to have_received(:start_typing).with(session: 'hybrid-test', chat_id: '5511999990000@c.us')
    expect(sleeps.size).to eq(1)
    expect(client).to have_received(:stop_typing)
  end

  it 'adds the per-character time, punctuation pauses and the first-chunk extra' do
    text = 'Já tenho o retorno para você, posso te ligar agora?' # 51 chars, uma vírgula, uma interrogação
    min = (51 * 24) + 90 + 320 + 700
    max = (51 * 38) + 90 + 320 + 1600

    expect(Array.new(10) { typing.delay_ms(outgoing(text)) }).to all(be_between(min, max))
  end

  it 'pauses on line breaks and list items' do
    plain = described_class.new(client, session: 's', chat_id: 'c', rng: Random.new(1)).delay_ms(outgoing('a b c'))
    listed = described_class.new(client, session: 's', chat_id: 'c', rng: Random.new(1)).delay_ms(outgoing("a\n- b\n1. c"))

    expect(listed - plain).to be >= (2 * 180) + (2 * 220)
  end

  it 'never takes the same time twice in a row for the same text' do
    message = outgoing('Posso te ligar agora?')

    expect(Array.new(5) { typing.delay_ms(message) }.uniq.size).to be > 1
  end

  it 'keeps every wait between 0.9 and 15 seconds' do
    expect(typing.delay_ms(outgoing('ok'))).to be >= 900
    expect(typing.delay_ms(outgoing('x ' * 2000))).to eq(15_000)
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
