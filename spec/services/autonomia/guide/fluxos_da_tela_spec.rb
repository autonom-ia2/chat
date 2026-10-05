require 'rails_helper'

# Conta 16 (05/10/2026): na tela de criar automação, o pedido longo trouxe fluxos da Prospecção e
# deixou de fora o da própria tela e o do Decisor. Os fluxos da tela agora entram sempre.
RSpec.describe Autonomia::Guide::FluxosDaTela do
  let(:account) { create(:account) }
  let!(:criar) { fluxo(1, "### Criar automacao conversando\n- rota: `automacoes_nova` - `/automacoes/nova`\n- cobre: automacoes_editar") }
  let!(:decisor) { fluxo(2, "### Usar um Decisor\n- rota: `automacoes_lista` - `/automacoes`\n- cobre: automacoes_nova, automacoes_editar") }
  let!(:lista) { fluxo(3, "### Ver automacoes\n- rota: `automacoes_lista` - `/automacoes`") }
  let!(:parecido) { fluxo(4, "### Outra tela\n- rota: `automacoes_nova_x` - `/x`") }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Guia', agent_type: 'support') }
  let(:source) do
    Autonomia::Agents::Source.create!(account: account, agent: agent, source_type: 'md', status: :ready,
                                      review_status: 'accepted', review_summary: 'Mapa do Guia.', quality_score: 9)
  end

  def fluxo(indice, conteudo)
    Autonomia::Agents::KnowledgeEntry.create!(account: account, agent: agent, source: source, chunk_index: indice,
                                              status: :ready, content: conteudo, embedding: [1.0] + Array.new(1535, 0.0))
  end

  it 'traz o fluxo da tela e os que dizem cobrir a tela, e só eles' do
    expect(described_class.para(agent, 'automacoes_nova')).to eq([criar, decisor])
    expect(described_class.para(agent, 'automacoes_editar')).to eq([criar, decisor])
  end

  it 'sem tela ou sem agente, não traz nada' do
    expect(described_class.para(agent, '')).to eq([])
    expect(described_class.para(nil, 'automacoes_nova')).to eq([])
  end

  it 'o Answerer põe os fixos antes dos achados, sem repetir e dentro do teto' do
    achados = Array.new(Autonomia::Agents::Config::ANSWER_TOP_K) { |i| instance_double(Autonomia::Agents::KnowledgeEntry, id: 100 + i) }
    achados[3] = decisor
    answerer = Autonomia::Agents::Answerer.new(agent: agent, query: 'oi', fixos: [criar, decisor])

    juntos = answerer.send(:com_fixos, achados)

    expect(juntos.first(2)).to eq([criar, decisor])
    expect(juntos.size).to eq(Autonomia::Agents::Config::ANSWER_TOP_K)
    expect(juntos.count { |trecho| trecho.id == decisor.id }).to eq(1)
  end
end
