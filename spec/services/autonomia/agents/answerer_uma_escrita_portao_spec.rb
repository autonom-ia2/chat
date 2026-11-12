require 'rails_helper'

# #2918, revisão (BAIXO): a chamada travada pela `UmaEscritaPorTurno` é recusa. No Testar e no Copiloto, o portão de
# confiança não pode tomar o turno por "leu dado de sistema" quando uma das escritas foi travada (#1361): conta como
# recusa no `anotar_leitura`, como qualquer outra.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false },
      fallback_message: 'Não tenho informação confiável. Vou chamar alguém da equipe.'
    )
  end

  before do
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Registrar pedido', slug: 'registrar_pedido',
                                    http_method: 'POST', endpoint_url: 'https://api.example.com/pedidos', param_schema: [])
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Tools::HttpExecutor, call: { pedido: 42 }.to_json))
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      executor.call(%w[c1 c2].map { |id| { 'name' => 'registrar_pedido', 'call_id' => id, 'arguments' => '{}' } })
      { text: { reply: 'Pedido registrado: 3 unidades por R$ 89.', confidence: 0.9, should_handoff: false, handoff_reason: nil,
                used_snippet_ids: [], answered_from_knowledge: false }.to_json }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def testar(uma_escrita_por_turno:)
    described_class.new(agent: agent, query: 'registra o pedido', uma_escrita_por_turno: uma_escrita_por_turno).answer
  end

  it 'sem a trava, as duas escritas devolvem dado, e o portão deixa passar (a linha de base)' do
    expect(testar(uma_escrita_por_turno: false).reply).to eq('Pedido registrado: 3 unidades por R$ 89.')
  end

  it 'com a segunda escrita travada, o turno tem recusa, e o portão barra como barra qualquer recusa', :aggregate_failures do
    resultado = testar(uma_escrita_por_turno: true)

    expect(resultado.handoff[:should]).to be(true)
    expect(resultado.reply).to eq(agent.fallback_message)
  end
end
