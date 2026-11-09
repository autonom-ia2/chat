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

  def com_trecho(alvo = agent)
    trecho = Autonomia::Agents::KnowledgeEntry.new(id: 7, content: 'Franquia: valor que fica por conta do segurado.')
    described_class.new(agent: alvo.reload, query: 'O que é franquia?', history: [], snippets: [trecho]).input
  end

  def contexto(entrada)
    entrada.map { |item| item[:content].to_s }.find { |texto| texto.include?('[CONTEXTO] Fonte de fatos') }
  end

  before { Autonomia::Agents::Fase2.ligar!(account) }

  context 'with the flag on' do
    before { account.enable_features!('agente_material_primeiro') }

    it 'puts the material of the agent before the other sources and asks for the source of a definition', :aggregate_failures do
      regra = builder.instructions

      expect(regra).to include(ordem, 'inclusive a definição de um termo', '`used_snippet_ids`')
      posicoes = ['(1) o [CONTEXTO]', '(2) os FATOS-ÂNCORA', '(3) resultados de ferramentas', '(4) o CONTEXTO DA CONTA',
                  '(5) o seu conhecimento geral'].map { |fonte| regra.index(fonte) }
      expect(posicoes).to all(be_present)
      expect(posicoes).to eq(posicoes.sort)
      expect(regra.index(ordem)).to be > regra.index('CONHECIMENTO GERAL DO MUNDO')
    end

    it 'keeps the general knowledge, definitions included, for what the material does not cover (Schengen)' do
      expect(builder.instructions).to include('CONHECIMENTO GERAL DO MUNDO', 'países de um tratado', 'definições, conceitos',
                                              'só para o que o [CONTEXTO] não cobre')
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

    it 'leaves the platform Guide (system_key) as it is, with pieces of the material', :aggregate_failures do
      guia = Autonomia::Agents::Agent.create!(account: account, name: 'Guia', agent_type: 'support', status: :active,
                                              enabled: true, instruction: 'Guie.', config: { 'system_key' => 'guia' })

      expect(builder(guia).instructions).not_to include(ordem)
      expect(com_trecho(guia).last[:role]).to eq('user')
      expect(contexto(com_trecho(guia))).not_to include('Se um trecho abaixo responde')
    end

    it 'leaves Lia (insurance_quote) as it is, with pieces of the material', :aggregate_failures do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                             enabled: true, instruction: 'Cote o seguro.')

      expect(builder(lia).instructions).not_to include(ordem)
      expect(com_trecho(lia).last[:role]).to eq('user')
      expect(contexto(com_trecho(lia))).not_to include('Se um trecho abaixo responde')
    end

    it 'leaves the segment block of the agent Builder as it is (it has no [CONTEXTO])' do
      expect(Autonomia::Agents::PromptParts::SegmentoDaConta.texto(account, marca['texto'])).to include('Use como referência.')
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
      expect(contexto(com_trecho)).not_to include('Se um trecho abaixo responde')
    end
  end
end
