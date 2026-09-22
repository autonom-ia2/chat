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

  # FATIA 2 DO #420: o Agente de Cotação usa a lista do deploy (`QuoteAgent::Builder.ferramentas_mantidas`),
  # e não a gravada em `native_tool_slugs`. Os outros tipos de agente continuam com a gravada (acima).
  it 'offers the deploy list to the quote agent, whatever list is stored in its config' do
    lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                           enabled: true, instruction: 'Cote.', config: { 'native_tool_slugs' => ['cotar_seguro'] })
    described_class.all.each { |tool| allow(tool).to receive(:available_for?).and_return(true) }

    expect(described_class.for_agent(lia).map(&:slug)).to eq(Autonomia::Insurance::QuoteAgent::Builder.ferramentas_mantidas(lia))
    expect(lia.reload.native_tool_slugs).to eq(['cotar_seguro'])
  end
end
