require 'rails_helper'

# #1755: a memória do cliente (Crm::Memoria::Leitor, #1601) chega ao modelo só com a Fase 2 e a flag `memoria_ia`, na
# posição desenhada, e os ids dos fatos enviados ficam no evento `replied`.
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda o cliente.')
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:placa) { linha_da_memoria(id: 812, rotulo: 'placa do pedido', valor: 'RIO2E19') }
  let(:bilhete) { linha_da_memoria(chave: 'bilhete.quer', rotulo: 'o cliente quer', valor: 'renovar o seguro auto', origem: :sistema) }
  let(:leitura) { leitura_da_memoria(antes: [bilhete], agora_fatos: [placa], ids: [812]) }
  let(:argumentos) { [] }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      argumentos << kwargs
      resultado = Autonomia::Agents::AnswerResult.new(reply: 'Certo!', confidence: 0.9, handoff: { should: false, reason: nil },
                                                      used_knowledge: [], answered_from_knowledge: false)
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  def responder
    ultima = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming,
                              content: 'Qual placa você anotou?')
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  def evento_replied
    Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id, event_type: :replied).sole
  end

  it 'com a Fase 2 e a flag, o Answerer recebe os blocos e o replied guarda os ids dos fatos enviados' do
    chamadas = memoria_do_crm(leitura)

    responder

    memoria = argumentos.sole[:memoria]
    expect(memoria.fatos).to include('RIO2E19')
    expect(memoria.antes).to include('renovar o seguro auto')
    expect(chamadas.sole).to include(finalidade: :responder, account: account, conversation: conversation, agent: agent)
    expect(evento_replied.metadata).to eq('memoria_fact_ids' => [812])
  end

  it 'com a flag memoria_ia desligada, o Leitor nem é chamado e o pedido fica como antes' do
    chamadas = memoria_do_crm(leitura, ligada: false)

    responder

    expect(argumentos.sole).not_to have_key(:memoria)
    expect(chamadas).to be_empty
    expect(evento_replied.metadata).to eq({})
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'nada de memória, mesmo com a flag' do
      chamadas = memoria_do_crm(leitura)

      responder

      expect(argumentos.sole).not_to have_key(:memoria)
      expect(chamadas).to be_empty
    end
  end

  it 'leitura vazia: o pedido fica como antes' do
    memoria_do_crm(leitura_da_memoria)

    responder

    expect(argumentos.sole).not_to have_key(:memoria)
  end

  it 'se o Leitor falhar, o turno segue sem memória e o erro vai ao rastreador com a conta' do
    memoria_do_crm(leitura)
    allow(Crm::Memoria::Leitor).to receive(:para).and_raise(ActiveRecord::StatementInvalid, 'falhou')
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).with(kind_of(ActiveRecord::StatementInvalid), account: account)
                                                    .and_return(rastreador)

    responder

    expect(argumentos.sole).not_to have_key(:memoria)
    expect(rastreador).to have_received(:capture_exception)
    expect(conversation.messages.outgoing.where(sender_type: 'AgentBot').pick(:content)).to eq('Certo!')
  end
end
