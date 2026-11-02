require 'rails_helper'

# #2458 (PR 2 do #2436): o Answerer escrevendo a resposta a um comentário de post. No formato do comentário, a regra do
# formato vai no pedido e nenhuma ferramenta vai ao modelo; na conversa (padrão), nada muda. Pelo HTTP de verdade do
# ResponsesClient (WebMock).
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Hubber', agent_type: 'support', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false })
  end
  let(:corpos) { [] }
  let(:formato) { Autonomia::Agents::Answerer::FormatoDoComentario }

  before do
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste' }))
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: 'Criar pedido', slug: 'criar_pedido', http_method: 'POST',
                                    endpoint_url: 'https://api.example.com/pedidos', param_schema: [])
    resposta = { reply: 'Te mandei no direct!', confidence: 0.9, should_handoff: false, handoff_reason: nil,
                 used_snippet_ids: [], answered_from_knowledge: false }.to_json
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      { status: 200, body: { output_text: resposta }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def responder(**opcoes)
    described_class.new(agent: agent, query: 'quanto custa?', feature: 'meta_ads_comentarios_ia_escreve', **opcoes).answer
  end

  it 'na conversa (padrão) as ferramentas vão ao modelo, sem a regra do comentário', :aggregate_failures do
    responder

    expect(corpos.first['tools'].to_a.pluck('name')).to include('criar_pedido')
    expect(corpos.first.to_json).not_to include('FORMATO DESTA RESPOSTA')
  end

  it 'no comentário público, a regra do formato vai junto da regra do turno e nenhuma ferramenta vai', :aggregate_failures do
    resultado = responder(formato: formato::PUBLICO, contexto_do_turno: 'REGRA DO TURNO X')

    expect(corpos.size).to eq(1)
    expect(corpos.first).not_to have_key('tools')
    expect(corpos.first.to_json).to include('REGRA DO TURNO X', formato.regra(formato::PUBLICO).first(60))
    expect(resultado.reply).to eq('Te mandei no direct!')
  end

  it 'no privado do comentário, a regra do privado' do
    responder(formato: formato::PRIVADO)

    expect(corpos.first.to_json).to include(formato.regra(formato::PRIVADO).first(60))
  end

  it 'recusa formato desconhecido antes de chamar o modelo', :aggregate_failures do
    expect { responder(formato: :story) }.to raise_error(ArgumentError, /formato desconhecido/)
    expect(corpos).to be_empty
  end
end
