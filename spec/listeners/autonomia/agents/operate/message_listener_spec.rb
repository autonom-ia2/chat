require 'rails_helper'

# chat#1489: a nossa IA não responde ao aviso de "mensagem não suportada" (pendente, falhou ou sem recuperação).
describe Autonomia::Agents::Operate::MessageListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true) }

  def created(attributes)
    message = create(:message, message_type: :incoming, account: account, inbox: inbox, conversation: conversation,
                               content: 'texto', content_attributes: attributes)
    Events::Base.new('message.created', Time.zone.now, message: message)
  end

  it 'chama a IA para mensagem comum do contato' do
    event = created({})

    expect { listener.message_created(event) }.to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
  end

  it 'não chama a IA para o aviso pendente de recuperação' do
    event = created('is_unsupported' => true, 'hybrid_recovery' => 'pending')

    expect { listener.message_created(event) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
  end

  it 'não chama a IA para o aviso sem recuperação nem para o que falhou' do
    expect { listener.message_created(created('is_unsupported' => true)) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)

    failed = created('is_unsupported' => true, 'hybrid_recovery' => 'failed')
    expect { listener.message_created(failed) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
  end

  it 'lê a marca com chave em símbolo (mensagem ainda em memória, recém-criada)' do
    event = created({})
    event.data[:message].content_attributes = { is_unsupported: true }

    expect { listener.message_created(event) }.not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
  end
end
