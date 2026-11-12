require 'rails_helper'

# #2918, decisão do coordenador (11/11): as 3 rodadas valem para todas as ferramentas do agente com pronta, inclusive a
# HTTP que escreve (o agente com ajudante já tem 6 com as mesmas ferramentas). O que este spec guarda: a rodada a mais
# não faz o nosso lado repetir nada. A ferramenta POST roda uma vez por pedido do modelo; chamada uma vez, não roda de
# novo. Pedida de novo, roda de novo, como "mais um igual", com outra `Idempotency-Key` (`ChaveDeIdempotencia`), o mesmo
# que já acontecia com duas chamadas na mesma rodada. Pelo HTTP de verdade do `ResponsesClient` (WebMock na OpenAI).
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
    Autonomia::Agents::Tool.create!(
      account: account, agent: agent, name: 'Registrar pedido', slug: 'registrar_pedido', http_method: 'POST',
      endpoint_url: 'https://erp.exemplo.test/pedidos', timeout_seconds: 10,
      param_schema: [{ name: 'numero', type: 'integer', description: 'Número do pedido', required: true }]
    )
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    conversation.update!(assignee_agent_bot_id: agent_bot.id)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :incoming,
                     content: 'registra o pedido 42')
    sistema_responde('{"status":"registrado"}', chaves: chaves)
  end

  def registrar(call_id)
    { output: [{ type: 'function_call', name: 'registrar_pedido', call_id: call_id, arguments: { numero: 42 }.to_json }] }
  end

  def o_modelo_responde(*respostas)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      { status: 200, body: respostas[corpos.size - 1].to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def responder
    described_class.new(conversation: conversation, agent_inbox: agent_inbox,
                        reply_to_message_id: conversation.messages.incoming.last.id).perform
  end

  it 'chamada uma vez, a ferramenta que escreve roda uma vez, embora o modelo ainda pudesse chamar', :aggregate_failures do
    o_modelo_responde(registrar('c1'), { output_text: resposta_final })

    result = responder

    expect(result.status).to eq(:replied)
    expect(chaves.size).to eq(1)
    expect(corpos.size).to eq(2)
    # A segunda ida ainda levava a ferramenta (rodada 2 de 3): ele podia chamar de novo, e não chamou.
    expect(corpos.last['tools'].to_a.pluck('name')).to include('registrar_pedido')
  end

  it 'pedida de novo pelo modelo, roda de novo, como outro pedido (outra Idempotency-Key)', :aggregate_failures do
    o_modelo_responde(registrar('c1'), registrar('c2'), { output_text: resposta_final })

    result = responder

    expect(result.status).to eq(:replied)
    expect(chaves.size).to eq(2)
    expect(chaves.uniq.size).to eq(2)
    expect(corpos.size).to eq(3)
  end
end
