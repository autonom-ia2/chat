require 'rails_helper'

# #1755: a memória do cliente (Crm::Memoria::Leitor, #1601) chega ao modelo só com a Fase 2, na posição desenhada, pelo
# caminho de verdade (Responder -> Answerer -> PromptBuilder, com o cliente HTTP dublado), e os ids dos fatos enviados
# ficam no evento `replied`, inclusive os que a cotação leu.
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
  let(:produto) { linha_da_memoria(id: 77, rotulo: 'produto', valor: 'seguro auto') }
  let(:leitura) { leitura_da_memoria(antes: [produto], agora_fatos: [placa]) }
  let(:pedidos) { [] }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    conversation.update!(ai_assignee: agent_bot)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'x'))
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(cliente).to receive(:create_with_tool_executor) do |input:, **|
      pedidos << input
      { text: { reply: 'Certo!', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                answered_from_knowledge: false }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def responder
    ultima = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming,
                              content: 'Qual placa você anotou?')
    described_class.new(conversation: conversation, agent_inbox: agent_inbox, reply_to_message_id: ultima.id).perform
  end

  def papeis_e_textos
    pedidos.sole.map { |item| [item[:role], item[:content].first[:text]] }
  end

  def evento_replied
    Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id, event_type: :replied).sole
  end

  it 'com a Fase 2, o "antes" vem antes do histórico, o estado como developer e os fatos logo antes da pergunta' do
    chamadas = memoria_do_crm(leitura)

    responder

    itens = papeis_e_textos
    antes = itens.index { |_papel, texto| texto.include?('ANTES DESTA CONVERSA') }
    estado = itens.index { |_papel, texto| texto.start_with?('ESTADO DESTA CONVERSA') }
    expect(itens[antes].first).to eq('user')
    expect(antes).to be < itens.index { |_papel, texto| texto == 'Qual placa você anotou?' }
    expect(itens[estado].first).to eq('developer')
    expect(itens[-2]).to match(['user', a_string_including('DESTE PEDIDO', 'RIO2E19')])
    expect(chamadas.sole).to include(finalidade: :responder, account: account, conversation: conversation, agent: agent)
    expect(evento_replied.metadata).to eq('memoria_fact_ids' => [77, 812])
  end

  it 'leitura vazia (flag desligada ou caixa fora da memória): o Answerer nem recebe memória, o pedido fica como antes' do
    memoria_do_crm(Crm::Memoria::Leitor::Leitura.vazia)
    expect(Autonomia::Agents::Answerer).to receive(:new).with(hash_excluding(:memoria)).and_call_original
    responder
    com_vazia = papeis_e_textos

    expect(com_vazia.flatten.join).not_to include('REGISTRO#', 'ESTADO DESTA CONVERSA')
    expect(evento_replied.metadata).to eq({})
  end

  describe 'sem a Fase 2' do
    let(:account) { conta_da_fase2(ligada: false) }

    it 'o Leitor nem é chamado' do
      chamadas = memoria_do_crm(leitura)

      responder

      expect(chamadas).to be_empty
      expect(papeis_e_textos.flatten.join).not_to include('REGISTRO#')
    end
  end

  it 'se o Leitor quebrar (erro de código do CRM), a IA responde assim mesmo e o erro vai ao rastreador' do
    allow(Crm::Memoria::Leitor).to receive(:para).and_raise(NoMethodError, 'quebrou')
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

    responder

    expect(conversation.messages.outgoing.where(sender_type: 'AgentBot').pick(:content)).to eq('Certo!')
  end

  it 'se a leitura falhar no banco, o turno segue sem memória e o erro vai ao rastreador com a conta' do
    allow(Crm::Memoria::Leitor).to receive(:para).and_raise(ActiveRecord::StatementInvalid, 'falhou')
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).with(kind_of(ActiveRecord::StatementInvalid), account: account)
                                                    .and_return(rastreador)

    responder

    expect(rastreador).to have_received(:capture_exception)
    expect(papeis_e_textos.flatten.join).not_to include('REGISTRO#')
    expect(conversation.messages.outgoing.where(sender_type: 'AgentBot').pick(:content)).to eq('Certo!')
  end

  it 'na entrega em pedaços, os ids vão no meta e o job os grava no replied' do
    memoria_do_crm(leitura)
    allow(Autonomia::Agents::Operate::ChunkedDeliveryJob).to receive(:set).and_return(Autonomia::Agents::Operate::ChunkedDeliveryJob)
    allow(Autonomia::Agents::Operate::ChunkedDeliveryJob).to receive(:perform_later)

    with_modified_env(AI_HUMANIZE_DELIVERY: 'true') { responder }

    expect(Autonomia::Agents::Operate::ChunkedDeliveryJob).to have_received(:perform_later)
      .with(anything, anything, anything, anything, 0, hash_including('memoria_fact_ids' => [77, 812]))
  end

  describe 'a Lia (Agente de Cotação, sem segmento da conta)' do
    let(:agent) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                       enabled: true, instruction: 'Cote seguro.')
    end

    it 'o "antes" é o primeiro item do pedido' do
      memoria_do_crm(leitura)

      responder

      expect(papeis_e_textos.first).to match(['user', a_string_including('ANTES DESTA CONVERSA')])
    end
  end
end
