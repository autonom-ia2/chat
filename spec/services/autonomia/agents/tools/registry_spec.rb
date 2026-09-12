require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Registry do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end
  let(:capabilities_tool) { Autonomia::Agents::Tools::Native::InsuranceCapabilities }

  it 'exposes every catalogued tool with a unique, well-formed slug' do
    slugs = described_class.slugs
    expect(slugs).to all(match(Autonomia::Agents::Tool::SLUG_FORMAT))
    expect(slugs.uniq).to eq(slugs)
    expect(described_class.find(capabilities_tool.slug)).to eq(capabilities_tool)
  end

  it 'offers nothing to an agent that turned no native tool on' do
    expect(described_class.for_agent(agent)).to be_empty
  end

  it 'offers a tool the agent turned on and that is available' do
    agent.update!(config: agent.config.merge('native_tool_slugs' => [capabilities_tool.slug]))
    allow(capabilities_tool).to receive(:available_for?).and_return(true)

    expect(described_class.for_agent(agent)).to eq([capabilities_tool])
  end

  it 'hides a tool whose prerequisite is missing instead of letting it fail in front of the customer' do
    agent.update!(config: agent.config.merge('native_tool_slugs' => [capabilities_tool.slug]))
    allow(capabilities_tool).to receive(:available_for?).and_return(false)

    expect(described_class.for_agent(agent)).to be_empty
  end

  it 'ignores an unknown slug left over from an old configuration' do
    agent.update!(config: agent.config.merge('native_tool_slugs' => %w[ferramenta_que_nao_existe]))
    expect(described_class.for_agent(agent)).to be_empty
  end

  it 'deduplicates a slug repeated in the configuration' do
    agent.update!(config: agent.config.merge('native_tool_slugs' => [capabilities_tool.slug] * 3))
    allow(capabilities_tool).to receive(:available_for?).and_return(true)

    expect(described_class.for_agent(agent).size).to eq(1)
  end

  # ENTREGA 8, TERMO 2 — o rollout é OBRIGATÓRIO, e não cortesia: uma ferramenta nova só existe para
  # o agente que a tem em `native_tool_slugs`. O agente 24 (conta 16) nasceu com a lista do Builder de
  # antes da entrega 8; sem o passo de dados (`rollout-proposta.sh`), a Lia de produção continuaria
  # sem a proposta individual, com o código deployado e a suíte verde.
  describe 'a ferramenta nova e o agente criado antes (entrega 8, termo 2)' do
    let(:proposta) { Autonomia::Agents::Tools::Native::InsuranceProposal }
    let(:lista_de_antes) { Autonomia::Insurance::QuoteAgent::Builder::TODAS_AS_TOOLS - [proposta.slug] }

    before { allow(proposta).to receive(:available_for?).and_return(true) }

    it 'nao a oferece ao agente que nasceu sem o slug, mesmo com o codigo no ar' do
      agent.update!(config: agent.config.merge('native_tool_slugs' => lista_de_antes))

      expect(described_class.for_agent(agent).map(&:slug)).not_to include(proposta.slug)
    end

    it 'passa a oferece-la quando o slug entra na lista do agente, como o rollout faz' do
      agent.update!(config: agent.config.merge('native_tool_slugs' => lista_de_antes + [proposta.slug]))

      expect(described_class.for_agent(agent).map(&:slug)).to include(proposta.slug)
    end

    it 'o Builder de hoje ja a liga em quem nasce agora' do
      expect(Autonomia::Insurance::QuoteAgent::Builder::TODAS_AS_TOOLS).to include(proposta.slug)
    end
  end
end
