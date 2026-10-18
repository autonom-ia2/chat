require 'rails_helper'

# #1428 (tema 6, parte 3, entrega B) — a PROVA DO AJUSTE NUNCA EXECUTA FERRAMENTA (decisão do Rodrigo: o teste não pode
# mexer em nada de verdade: agenda, HTTP, CRM, mensagens). Com `prova: true`, o pedido à OpenAI sai sem `tools` e, mesmo
# que a resposta peça uma chamada de função, nada roda do nosso lado. Pelo HTTP de verdade do ResponsesClient (WebMock).
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Hubber', agent_type: 'support', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:corpos) { [] }
  let(:resposta_ok) do
    { reply: 'Em até 2 frases: temos auto e vida.', confidence: 0.9, should_handoff: false, handoff_reason: nil,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    # Uma ferramenta HTTP que ESCREVE (POST) ligada ao agente: no Testar ela iria ao modelo.
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Criar pedido', slug: 'criar_pedido', http_method: 'POST',
                                    endpoint_url: 'https://api.example.com/pedidos', param_schema: [])
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_call_original
    allow_any_instance_of(Autonomia::Agents::Tools::Bound).to receive(:execute).and_call_original # rubocop:disable RSpec/AnyInstance
  end

  def openai_devolve(payload)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def provar
    described_class.new(agent: agent, query: 'Quanto custa?', feature: 'agente_prova_do_ajuste', prova: true).answer
  end

  it 'o Testar de sempre manda a ferramenta ao modelo (a linha de base do que a prova tira)' do
    openai_devolve(output_text: resposta_ok)

    described_class.new(agent: agent, query: 'Quanto custa?', feature: 'agente_teste').answer

    expect(corpos.first['tools'].to_a.pluck('name')).to include('criar_pedido')
  end

  it 'a prova manda o pedido sem tools nenhuma (nem busca na web) e responde', :aggregate_failures do
    openai_devolve(output_text: resposta_ok)

    resultado = provar

    expect(corpos.size).to eq(1)
    expect(corpos.first).not_to have_key('tools')
    expect(resultado.reply).to eq('Em até 2 frases: temos auto e vida.')
  end

  it 'mesmo que o modelo peça uma função, nada é executado e a prova sai como IA indisponível', :aggregate_failures do
    openai_devolve(output: [{ type: 'function_call', name: 'criar_pedido', call_id: 'c1', arguments: '{}' }])

    resultado = provar

    expect(corpos.size).to eq(1)
    expect(Autonomia::Agents::Tools::HttpExecutor).not_to have_received(:new)
    expect(WebMock).not_to have_requested(:post, 'https://api.example.com/pedidos')
    expect(resultado.error).to eq('ai_unavailable')
  end

  it 'nenhum Bound é montado nem executado na prova (agenda, HTTP, especialista ou ajudante)' do
    openai_devolve(output_text: resposta_ok)
    allow(Autonomia::Agents::Tools::Bound).to receive(:for_agent).and_call_original

    provar

    expect(Autonomia::Agents::Tools::Bound).not_to have_received(:for_agent)
  end

  it 'teto de 30 s e sem nova tentativa, com a feature da prova' do
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create_with_tool_executor).and_return(text: resposta_ok)

    provar

    expect(Crm::Ai::ResponsesClient).to have_received(:new)
      .with(hash_including(feature: 'agente_prova_do_ajuste', max_retries: 0))
    expect(cliente).to have_received(:create_with_tool_executor).with(hash_including(tools: nil, timeout: 30))
  end

  it 'fora da prova, nada muda: sem o teto curto e com as tentativas de sempre' do
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create_with_tool_executor).and_return(text: resposta_ok)

    described_class.new(agent: agent, query: 'Quanto custa?').answer

    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_excluding(:max_retries))
    expect(cliente).to have_received(:create_with_tool_executor).with(hash_excluding(:timeout))
  end
end
