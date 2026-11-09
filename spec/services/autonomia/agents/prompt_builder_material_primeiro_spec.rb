require 'rails_helper'

# #2801 (Refs #1431) — o material do próprio agente vem primeiro. Com a flag `agente_material_primeiro`, a regra de
# resposta dá a ordem das fontes e o bloco do segmento vale só quando o material não traz o assunto: a definição que está
# no material sai dele, com a fonte, e não da memória do modelo nem do texto do segmento. O conhecimento geral (fix
# "Schengen") continua para o que o material não cobre. A Lia e o Guia ficam como estão.
RSpec.describe Autonomia::Agents::PromptBuilder do
  let(:account) { create(:account) }
  let(:marca) { { 'segmento' => 'seguros/corretora', 'versao' => 'aaaabbbbcccc', 'texto' => "Ramo: seguros.\nVocabulário: franquia." } }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'support', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: { 'base' => marca })
  end
  let(:ordem) { 'ORDEM DAS FONTES' }

  def builder(alvo = agent, audience: :customer)
    described_class.new(agent: alvo.reload, query: 'O que é franquia?', history: [], audience: audience)
  end

  def segmento(alvo = agent)
    builder(alvo).input.map { |item| item[:content].to_s }.find { |texto| texto.include?('CONTEXTO DA CONTA') }
  end

  before { Autonomia::Agents::Fase2.ligar!(account) }

  context 'with the flag on' do
    before { account.enable_features!('agente_material_primeiro') }

    it 'puts the material of the agent before the other sources and asks for the source of a definition', :aggregate_failures do
      regra = builder.instructions

      expect(regra).to include(ordem, 'inclusive a definição de um termo', '`used_snippet_ids`')
      expect(regra.index('[CONTEXTO]', regra.index(ordem))).to be < regra.index('conhecimento geral', regra.index(ordem))
    end

    it 'keeps the general knowledge for what the material does not cover (Schengen), without the definitions', :aggregate_failures do
      regra = builder.instructions

      expect(regra).to include('CONHECIMENTO GERAL DO MUNDO', 'países de um tratado', 'só para o que o [CONTEXTO] não cobre')
      expect(regra).not_to include('definições, conceitos')
    end

    it 'reminds the order next to the pieces of the material' do
      trecho = Autonomia::Agents::KnowledgeEntry.new(id: 7, content: 'Franquia: valor que fica por conta do segurado.')
      contexto = described_class.new(agent: agent.reload, query: 'O que é franquia?', history: [], snippets: [trecho])
                                .input.map { |item| item[:content].to_s }.find { |texto| texto.include?('[CONTEXTO] Fonte de fatos') }

      expect(contexto).to include('Se um trecho abaixo responde à pergunta, inclusive a definição de um termo')
    end

    it 'ends the input with the reminder, after the question, when there are pieces of the material', :aggregate_failures do
      trecho = Autonomia::Agents::KnowledgeEntry.new(id: 7, content: 'Franquia: valor que fica por conta do segurado.')
      entrada = described_class.new(agent: agent.reload, query: 'O que é franquia?', history: [], snippets: [trecho]).input

      expect(entrada.last[:role]).to eq('developer')
      expect(entrada.last[:content].to_s).to include('`used_snippet_ids`')
      expect(entrada[-2][:content].to_s).to include('O que é franquia?')
    end

    it 'sends no reminder at the end without pieces of the material' do
      expect(builder.input.last[:role]).to eq('user')
    end

    it 'tells the segment block to wait for the material' do
      expect(segmento).to include('só quando o [CONTEXTO] não trouxer o assunto')
    end

    it 'leaves the platform Guide strict, with no order of sources' do
      expect(builder(audience: :system).instructions).not_to include(ordem)
    end

    it 'leaves Lia (insurance_quote) as it is' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                             enabled: true, instruction: 'Cote o seguro.')

      expect(builder(lia).instructions).not_to include(ordem)
    end
  end

  context 'with the flag off' do
    it 'keeps the rule and the segment block as before', :aggregate_failures do
      expect(builder.instructions).not_to include(ordem)
      expect(builder.instructions).to include('definições, conceitos')
      trecho = Autonomia::Agents::KnowledgeEntry.new(id: 7, content: 'Franquia: valor que fica por conta do segurado.')
      expect(described_class.new(agent: agent.reload, query: 'O que é franquia?', history: [], snippets: [trecho])
                            .input.last[:role]).to eq('user')
      expect(segmento).to include('Use como referência.')
      expect(segmento).not_to include('só quando o [CONTEXTO]')
    end
  end
end
