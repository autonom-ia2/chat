require 'rails_helper'

# chat#1489 × ReplyJob (pedido da sessão Agentes IA): a mensagem recuperada acorda a IA pelo caminho normal — fase
# 'trigger', debounce e 'settle' — e o Responder responde UMA vez. Se o cliente manda outra mensagem nessa janela, o
# settle da recuperada aborta e só a mais nova é respondida.
#
# Aqui, o token do debounce (`autonomia_debounce.pending_message_id`). Com a Fase 2 ligada (#1627, na main desde
# 15/10), a posse do turno e o `turno_superado`: reply_job_recuperacao_fase2_spec.rb.
#
# Checklist do merge com o #1627 (feito em 16/10):
# [x] spec com a Fase 2 ligada: a recuperada pega a posse do turno e responde uma vez (a posse fica: dedupe);
# [x] spec do `turno_superado`: cliente manda outra durante a chamada à IA -> resposta da recuperada descartada e só a
#     mais nova responde;
# [x] rodar os specs do responder e do reply_job;
# [x] eventos: o #1627 usa o 8 (skipped_assunto_atrasou), o #1669 o 9 (silenciado_pessoa_respondeu); o #1489 usa 10,
#     11, 12, 13 e 14 (skipped_recuperada_so_contexto);
# [x] mantidas as duas pontas do enum (AgentEvent), do ALLOWED_REASONS (EventLogger) e da posse no responder
#     (`so_contexto_interno` entra nos SILENCIOS_DE_FALHA, como o `vazio`: solta a posse).
# [ ] ligar a flag `whatsapp_hybrid_recovery` na conta 1 (Fase 2) só depois do #1637 (EsperaDoAssunto contando o teto a
#     partir de max(created_at, hybrid_recovered_at)); nas contas sem Fase 2, sem essa trava.
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

  it 'a recuperação grava a marca do turno e agenda o settle do ReplyJob para a mensagem recuperada' do
    expect { recover! }.to have_enqueued_job(reply_job).with(conversation.id, message.id, 'settle').exactly(:once)
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
