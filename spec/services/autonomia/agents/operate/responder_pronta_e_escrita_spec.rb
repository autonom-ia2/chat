require 'rails_helper'

# #2918, revisão de segurança: o Rodrigo autorizou CONSULTAR até 3 vezes, não escrever. Quando as rodadas a mais vêm das
# prontas, a ferramenta HTTP que escreve (POST) roda no máximo uma vez por turno: na segunda chamada, o modelo lê
# "esta ação já foi feita neste turno" e o sistema de fora não é chamado. Sem isso, um texto injetado pelo cliente fazia
# o POST rodar até 3 vezes, cada vez com outra `Idempotency-Key`. A leitura (GET e as prontas) segue livre nas 3 rodadas,
# e o agente com ajudante segue como antes. Pelo HTTP de verdade do `ResponsesClient` (WebMock na OpenAI).
RSpec.describe Autonomia::Agents::Operate::Responder do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:agent_inbox) { Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: agent_bot) }
  let(:corpos) { [] }
  let(:chaves) { [] }
  let(:resposta_final) do
    { reply: 'Pedido 42 registrado.', confidence: 0.9, should_handoff: false, handoff_reason: nil, used_snippet_ids: [],
      answered_from_knowledge: false }.to_json
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false') { example.run }
  end

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
    incluir_pronta('ncm', conta: account, agente: agent)
    ferramenta('registrar_pedido', 'POST')
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming,
                     content: 'registra o pedido 42')
    sistema_responde('{"status":"registrado"}', chaves: chaves)
  end

  def ferramenta(slug, metodo)
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: slug.humanize, slug: slug, http_method: metodo,
      endpoint_url: "https://erp.exemplo.test/#{slug}", timeout_seconds: 10,
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
  end

  def chamada(call_id, slug = 'registrar_pedido')
    { type: 'function_call', name: slug, call_id: call_id, arguments: { numero: 42 }.to_json }
  end

  def o_modelo_responde(*respostas)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      { status: 200, body: respostas[corpos.size - 1].to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def saida_de(corpo, call_id)
    corpo['input'].find { |item| item['type'] == 'function_call_output' && item['call_id'] == call_id }&.dig('output')
  end

  def responder
    described_class.new(conversation: conversation, agent_inbox: agent_inbox,
                        reply_to_message_id: conversation.messages.incoming.last.id).perform
  end

  # Registro do comportamento (não teve vermelho): a rodada a mais não faz o nosso lado repetir nada sozinho.
  it 'chamada uma vez, a ferramenta que escreve roda uma vez, embora o modelo ainda pudesse chamar', :aggregate_failures do
    o_modelo_responde({ output: [chamada('c1')] }, { output_text: resposta_final })

    result = responder

    expect(result.status).to eq(:replied)
    expect(chaves.size).to eq(1)
    expect(corpos.size).to eq(2)
    # A segunda ida ainda levava a ferramenta (rodada 2 de 3): ele podia chamar de novo, e não chamou.
    expect(corpos.last['tools'].to_a.pluck('name')).to include('registrar_pedido')
  end

  it 'pedida de novo em outra rodada, não roda: o modelo lê que o pedido não foi feito', :aggregate_failures do
    o_modelo_responde({ output: [chamada('c1')] }, { output: [chamada('c2')] }, { output_text: resposta_final })

    result = responder

    expect(result.status).to eq(:replied)
    expect(chaves.size).to eq(1)
    expect(corpos.size).to eq(3)
    expect(saida_de(corpos[1], 'c1')).to eq('{"status":"registrado"}')
    expect(saida_de(corpos[2], 'c2')).to eq(Autonomia::Agents::Tools::UmaEscritaPorTurno::NAO_FEITA)
  end

  it 'duas chamadas na mesma rodada: só a primeira roda', :aggregate_failures do
    o_modelo_responde({ output: [chamada('c1'), chamada('c2')] }, { output_text: resposta_final })

    responder

    expect(chaves.size).to eq(1)
    expect(saida_de(corpos[1], 'c2')).to eq(Autonomia::Agents::Tools::UmaEscritaPorTurno::NAO_FEITA)
  end

  # Revisão (ALTO): a ferramenta só conta como feita depois de rodar sem recusa nem erro. A primeira escrita que volta 4xx
  # não trava a segunda: o modelo corrige o dado e tenta de novo, e o agente não confirma ao cliente o que não aconteceu.
  it 'a escrita que falhou (4xx) não trava: o modelo corrige e a segunda roda', :aggregate_failures do
    executor = instance_double(Autonomia::Agents::Tools::HttpExecutor)
    respostas = [-> { raise Autonomia::Agents::Tools::HttpExecutor::Error.new('tool_http_error: 422', status: 422) },
                 -> { '{"status":"registrado"}' }]
    allow(executor).to receive(:call) { respostas.shift.call }
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_return(executor)
    o_modelo_responde({ output: [chamada('c1')] }, { output: [chamada('c2')] }, { output_text: resposta_final })

    responder

    expect(executor).to have_received(:call).twice
    expect(saida_de(corpos[2], 'c2')).to eq('{"status":"registrado"}')
  end

  # Revisão (BAIXO): o 2xx do sistema de fora é feito, mesmo com `{"error"}` no corpo. A chave de idempotência já avançou
  # com o 2xx (`ChaveDeIdempotencia.concluir`): liberar outra tentativa podia duplicar a escrita. Não feito é só a recusa
  # nossa ou o 4xx/5xx.
  it 'o 2xx com "error" no corpo conta como feito: a segunda chamada não roda', :aggregate_failures do
    executor = instance_double(Autonomia::Agents::Tools::HttpExecutor, call: '{"error":"pedido_duplicado"}')
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_return(executor)
    o_modelo_responde({ output: [chamada('c1')] }, { output: [chamada('c2')] }, { output_text: resposta_final })

    responder

    expect(executor).to have_received(:call).once
    expect(saida_de(corpos[2], 'c2')).to eq(Autonomia::Agents::Tools::UmaEscritaPorTurno::NAO_FEITA)
  end

  it 'o texto da trava diz a verdade: este pedido não foi feito' do
    expect(Autonomia::Agents::Tools::UmaEscritaPorTurno::NAO_FEITA).to include('NÃO foi feito')
  end

  it 'a leitura (GET) segue livre nas 3 rodadas', :aggregate_failures do
    ferramenta('consultar_pedido', 'GET')
    o_modelo_responde({ output: [chamada('c1', 'consultar_pedido')] }, { output: [chamada('c2', 'consultar_pedido')] },
                      { output_text: resposta_final })

    responder

    expect(chaves.size).to eq(2)
    expect(saida_de(corpos[2], 'c2')).to eq('{"status":"registrado"}')
  end

  it 'o agente com ajudante (que também tem pronta) segue como antes: pedida de novo, a escrita roda de novo', :aggregate_failures do
    account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_fase2' => true))
    vincular(agent, criar_ajudante(account))
    o_modelo_responde({ output: [chamada('c1')] }, { output: [chamada('c2')] }, { output_text: resposta_final })

    responder

    expect(chaves.size).to eq(2)
    expect(chaves.uniq.size).to eq(2)
    expect(saida_de(corpos[2], 'c2')).to eq('{"status":"registrado"}')
  end
end
