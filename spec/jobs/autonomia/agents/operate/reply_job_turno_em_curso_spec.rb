require 'rails_helper'

# #2154 (flag `agente_so_informa`): o turno do agente começa na mensagem do cliente (ReplyJob#trigger), para a IA de
# Atribuição não entregar a conversa enquanto ele responde. O settle solta a marca quando o turno acaba, por qualquer
# caminho, inclusive um prepend do Responder que pula o turno sem chegar ao corpo dele; fica só quando o turno segue.
RSpec.describe Autonomia::Agents::Operate::ReplyJob do
  include_context 'with crm responsible agent'

  let(:turno) { Autonomia::Agents::Operate::TurnoEmCurso }
  let(:mensagem) { create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi') }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_AGENT_MEDIA: 'false', AI_HUMANIZE_DELIVERY: 'false') { example.run }
  end

  before do
    account.enable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
    Redis::Alfred.delete(turno.chave(conversation.id))
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
  end

  def ia_responde(texto = 'Claro, te ajudo.')
    answer = Autonomia::Agents::AnswerResult.new(reply: texto, confidence: 0.9, handoff: { should: false, reason: nil },
                                                 used_knowledge: [], answered_from_knowledge: false)
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: answer))
  end

  def gatilho!(msg = mensagem) = described_class.perform_now(conversation.id, msg.id, 'trigger')

  def settle!(msg = mensagem) = described_class.perform_now(conversation.id, msg.id, 'settle')

  def respostas = conversation.messages.outgoing.where(sender_type: 'AgentBot', private: false)

  it 'a mensagem do cliente abre o turno, com o id dela', :aggregate_failures do
    gatilho!

    expect(Redis::Alfred.get(turno.chave(conversation.id))).to eq(mensagem.id.to_s)
    expect(Redis::Alfred.ttl(turno.chave(conversation.id))).to be > 0
  end

  it 'sem a flag, não abre' do
    account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)

    gatilho!

    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  it 'o agente respondeu: o settle solta a marca', :aggregate_failures do
    ia_responde
    gatilho!

    settle!

    expect(respostas.count).to eq(1)
    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  it 'a IA falhou: o settle solta a marca também' do
    allow(Autonomia::Agents::Answerer).to receive(:new).and_raise(StandardError, 'caiu')
    gatilho!

    settle!

    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  # O Waha::RichNative::AgentTurnGuard (prepend no Responder) cala o turno só de mensagens apagadas pelo cliente sem
  # chamar o corpo do Responder. A marca não pode ficar presa até o teto do turno.
  it 'o guard do WAHA pulou o turno (só mensagem apagada pelo cliente): a marca sai', :aggregate_failures do
    ia_responde
    mensagem.update!(content_attributes: { Waha::RichNative::TurnKinds::DELETED_KEY => Time.current.iso8601 })
    # A caixa da fábrica é de widget: as mensagens automáticas dele (saudação, pedir e-mail) fechariam o turno do cliente.
    conversation.messages.template.delete_all
    gatilho!

    settle!

    expect(respostas.count).to eq(0)
    expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  it 'o turno já foi respondido (a posse já é deste dono): o settle repetido solta a marca' do
    ia_responde
    gatilho!
    settle!
    turno.abrir(conversation.id, mensagem.id)

    settle!

    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  # Dois settles do mesmo turno: o primeiro tem a posse e está na IA quando o segundo roda. O segundo não pode soltar a
  # marca do primeiro (a avaliação pendente entregaria a conversa no meio da resposta).
  it 'dois settles concorrentes: o segundo não solta a marca do primeiro, que solta ao terminar', :aggregate_failures do
    gatilho!
    marca_durante_a_ia = nil
    answer = Autonomia::Agents::AnswerResult.new(reply: 'Claro, te ajudo.', confidence: 0.9, handoff: { should: false, reason: nil },
                                                 used_knowledge: [], answered_from_knowledge: false)
    answerer = instance_double(Autonomia::Agents::Answerer)
    allow(answerer).to receive(:answer) do
      settle! # o segundo settle, com outro job_id, enquanto o primeiro está na IA
      marca_durante_a_ia = Redis::Alfred.get(turno.chave(conversation.id))
      answer
    end
    allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer)

    settle!

    expect(marca_durante_a_ia).to eq(mensagem.id.to_s)
    expect(respostas.count).to eq(1)
    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  it 'a entrega em pedaços assumiu o turno: a marca fica com a cadeia', :aggregate_failures do
    allow_any_instance_of(Autonomia::Agents::Operate::TypingIndicator).to receive(:on) # rubocop:disable RSpec/AnyInstance
    ia_responde("#{'Primeira parte da resposta, longa o bastante para virar um pedaço. ' * 4}\n\n#{'E a segunda parte. ' * 12}")
    gatilho!

    with_modified_env(AI_HUMANIZE_DELIVERY: 'true') { settle! }

    expect(Redis::Alfred.get(turno.chave(conversation.id))).to eq(mensagem.id.to_s)
    expect(Redis::Alfred.ttl(turno.chave(conversation.id))).to be_between(1, turno::TTL_DA_CADEIA.to_i)
  end

  it 'uma pessoa assumiu na janela do debounce: o settle solta a marca' do
    gatilho!
    conversation.update!(assignee: admin)

    settle!

    expect(turno.em_curso?(conversation.id)).to be(false)
  end

  it 'sem a flag, o settle não vai ao Redis' do
    account.disable_features!(Autonomia::Agents::AgenteSoInforma::FLAG)
    allow(turno).to receive(:soltar)
    gatilho!
    conversation.update!(assignee: admin)

    settle!

    expect(turno).not_to have_received(:soltar)
  end
end
