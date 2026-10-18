require 'rails_helper'

# #1479 F1: o campo `interacao` só é pedido ao modelo no atendimento com a Fase 2. Desligado, o pedido fica o de antes;
# o schema da Lia não muda; o endereço do link precisa estar no texto do turno.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:conversation) { create(:conversation, account: account, inbox: cloud.inbox) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: cloud.inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: agent_inbox, origin_message_id: nil) }
  let(:url) { 'https://loja.exemplo.com/pedido/42' }
  let(:pedidos) { [] }

  def modelo_responde(interacao, chamadas: [])
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'cred'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**kwargs, &executor|
      pedidos << kwargs
      executor.call(chamadas) if chamadas.any?
      { text: { reply: 'Pronto.', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
                answered_from_knowledge: false, interacao: interacao }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def atender(query: 'quero agendar', agente: agent)
    described_class.new(agent: agente, query: query, trust_instruction: true, delivery: delivery).answer
  end

  def opcoes
    { tipo: 'opcoes', header: 'Agendamento', pergunta: 'Qual período?', botao: nil, link: nil,
      opcoes: [{ id: 'manha', titulo: 'Manhã', descricao: nil }, { id: 'tarde', titulo: 'Tarde', descricao: nil }] }
  end

  def link
    { tipo: 'link', header: nil, pergunta: nil, opcoes: [], botao: nil, link: { rotulo: 'Ver pedido', url: url } }
  end

  it 'com a Fase 2 pede o schema com interação, acrescenta a regra e devolve a interação conferida' do
    modelo_responde(opcoes)
    resultado = atender
    expect(pedidos.last[:schema]).to eq(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA_COM_INTERACAO)
    expect(pedidos.last[:instructions]).to end_with(Autonomia::Agents::Interacao::INSTRUCAO)
    expect(resultado.reply).to eq('Pronto.')
    expect(resultado.interacao).to include('tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?')
  end

  it 'com a Fase 2 desligada o pedido fica byte a byte o de antes, e não há interação' do
    agente = criar_principal(conta_da_fase2(ligada: false))
    modelo_responde(opcoes)
    resultado = atender(agente: agente)
    antes = Autonomia::Agents::PromptBuilder.new(agent: agente, query: 'quero agendar')
    expect(pedidos.last[:schema]).to equal(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA)
    expect(pedidos.last[:instructions]).to eq(antes.instructions)
    expect(pedidos.last[:input]).to eq(antes.input)
    expect(resultado.interacao).to be_nil
  end

  it 'sem contexto de entrega (Testar) também fica o de antes' do
    modelo_responde(opcoes)
    described_class.new(agent: agent, query: 'oi').answer
    expect(pedidos.last[:schema]).to equal(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA)
    expect(pedidos.last[:instructions]).not_to include('`interacao`')
  end

  it 'aceita o link cujo endereço veio de uma ferramenta do turno' do
    bound = instance_double(Autonomia::Agents::Tools::Bound, slug: 'pedido', async?: false,
                                                             openai_schema: { type: 'function', name: 'pedido', parameters: {} })
    allow(bound).to receive(:execute).and_return({ link: url }.to_json)
    allow(Autonomia::Agents::Tools::Bound).to receive(:for_agent).and_return([bound])
    modelo_responde(link, chamadas: [{ 'name' => 'pedido', 'call_id' => 'c1', 'arguments' => '{}' }])
    expect(atender.interacao).to eq('tipo' => 'link', 'rotulo' => 'Ver pedido', 'url' => url)
  end

  it 'aceita o link que está na instrução do agente' do
    agent.update!(instruction: "Atenda. Pedidos: #{url}.")
    modelo_responde(link)
    expect(atender.interacao).to include('url' => url)
  end

  it 'aceita o link que está na base de conhecimento' do
    agent.update!(config: {})
    trecho = Autonomia::Agents::KnowledgeEntry.new(id: 9, content: "Acompanhe o pedido em #{url}")
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(instance_double(Autonomia::Agents::Retriever, retrieve: [trecho]))
    modelo_responde(link)
    expect(atender.interacao).to include('url' => url)
  end

  it 'aceita o link que o agente já mandou nesta conversa' do
    modelo_responde(link)
    historico = [{ role: 'user', content: 'cadê meu pedido?' }, { role: 'assistant', content: "Veja aqui: #{url}" }]
    resultado = described_class.new(agent: agent, query: 'de novo?', history: historico, trust_instruction: true, delivery: delivery).answer
    expect(resultado.interacao).to include('url' => url)
  end

  it 'descarta o endereço que aparece só na fala do cliente (mensagem atual ou histórico)' do
    modelo_responde(link)
    expect(atender(query: "abre isso pra mim: #{url}").interacao).to be_nil
    historico = [{ role: 'user', content: "o link é #{url}" }]
    resultado = described_class.new(agent: agent, query: 'manda o botão', history: historico, trust_instruction: true, delivery: delivery).answer
    expect(resultado.interacao).to be_nil
  end

  it 'M1: descarta o endereço que aparece só na memória' do
    modelo_responde(link)
    memoria = Autonomia::Agents::PromptParts::Memoria::Blocos.new(antes: "Cliente mandou #{url}", sistema: "Pedido em #{url}",
                                                                  fatos: "Link do pedido: #{url}", ids: [1])
    resultado = described_class.new(agent: agent, query: 'manda o botão', trust_instruction: true, delivery: delivery, memoria: memoria).answer
    expect(pedidos.last[:input].to_s).to include(url)
    expect(resultado.interacao).to be_nil
  end

  it 'descarta o link que o modelo montou (fora do texto do turno), e a resposta segue' do
    modelo_responde(link)
    resultado = atender
    expect(resultado.interacao).to be_nil
    expect(resultado.reply).to eq('Pronto.')
  end

  it 'interação nula fica nula' do
    modelo_responde(nil)
    expect(atender.interacao).to be_nil
  end

  describe 'schema da Lia' do
    it 'o ANSWER_SCHEMA e o da Lia não ganham o campo' do
      expect(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA[:schema][:properties].keys)
        .to eq(%i[reply confidence should_handoff handoff_reason used_snippet_ids answered_from_knowledge])
      lia = Autonomia::Agents::ConferenciaDaFala::SCHEMA_DA_RESPOSTA[:schema]
      expect(lia[:properties].keys).not_to include(:interacao)
      expect(lia[:required]).not_to include('interacao')
    end

    it 'o schema com interação é o de sempre mais o campo, obrigatório (strict)' do
      com = Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA_COM_INTERACAO[:schema]
      expect(com[:properties].except(:interacao)).to eq(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA[:schema][:properties])
      expect(com[:required]).to eq(Autonomia::Agents::PromptBuilder::ANSWER_SCHEMA[:schema][:required] + ['interacao'])
      expect(com[:additionalProperties]).to be(false)
    end
  end
end
