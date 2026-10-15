require 'rails_helper'

# chat#1489 × ReplyJob (pedido da sessão Agentes IA): a mensagem recuperada acorda a IA pelo caminho normal — fase
# 'trigger', debounce e 'settle' — e o Responder responde UMA vez. Se o cliente manda outra mensagem nessa janela, o
# settle da recuperada aborta e só a mais nova é respondida.
#
# Mecanismo coberto aqui: o token do debounce (`autonomia_debounce.pending_message_id`) que está na main da base desta
# PR (cd9d030aa7). A posse do turno da Fase 2 ("um turno, uma ordem", PR #1627) ainda não está na main: este spec
# ganha o caso com ela ligada quando o #1627 entrar e a main for mesclada aqui.
#
# Checklist depois do #1627 (mesclar a main nesta branch):
# [ ] spec com a Fase 2 ligada: a recuperada pega a posse do turno, responde uma vez e solta;
# [ ] spec do `turno_superado`: cliente manda outra durante a chamada à IA -> resposta da recuperada descartada e só a
#     mais nova responde;
# [ ] rodar os specs do responder e do reply_job;
# [ ] conferir o número do evento: o #1627 usa o 8 (skipped_assunto_atrasou); o #1489 usa 9, 10 e 11.
describe Autonomia::Agents::Operate::ReplyJob do
  include_context 'with a pending unsupported hybrid message'

  let(:reply_job) { described_class }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:answered) { [] }

  before do
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Operate).to receive(:eligible_agent_inbox).and_return(agent_inbox)
    allow(Autonomia::Agents::Operate::Responder).to receive(:new) do |reply_to_message_id:, **|
      answered << reply_to_message_id
      instance_double(Autonomia::Agents::Operate::Responder, perform: nil)
    end
    stub_engine
  end

  def recover!
    WhatsappHybrid::UnsupportedRecovery.new(message).attempt!
  end

  it 'a recuperação enfileira a fase trigger do ReplyJob para a mensagem recuperada' do
    expect { recover! }.to have_enqueued_job(reply_job).with(conversation.id, message.id).exactly(:once)
  end

  it 'trigger, debounce e settle: o Responder responde uma vez, à mensagem recuperada' do
    perform_enqueued_jobs(only: reply_job) { recover! }

    expect(answered).to eq([message.id])
    expect(conversation.reload.additional_attributes.dig('autonomia_debounce', 'pending_message_id')).to eq(message.id)
  end

  it 'nova tentativa depois de recuperada não chama a IA de novo' do
    perform_enqueued_jobs(only: reply_job) do
      recover!
      recover!
      WhatsappHybrid::RecoverUnsupportedJob.perform_now(message.id)
    end

    expect(answered).to eq([message.id])
  end

  it 'o cliente manda outra durante a janela: a recuperada é descartada e só a mais nova responde' do
    recover!
    reply_job.perform_now(conversation.id, message.id) # trigger da recuperada

    newer = create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox,
                             sender: contact, content: 'oi? alguém aí?')
    reply_job.perform_now(conversation.id, newer.id) # trigger da mais nova (o listener faz isso)

    reply_job.perform_now(conversation.id, message.id, 'settle')
    reply_job.perform_now(conversation.id, newer.id, 'settle')

    expect(answered).to eq([newer.id])
  end
end
