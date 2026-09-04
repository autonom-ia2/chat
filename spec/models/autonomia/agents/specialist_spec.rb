require 'rails_helper'

RSpec.describe Autonomia::Agents::Specialist do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end

  def create_specialist(**attrs)
    described_class.create!({
      agent: agent, name: 'Especialista de Automóvel', description: 'cotação de seguro de automóvel',
      instruction: 'Você cota seguro de automóvel.'
    }.merge(attrs))
  end

  it 'exposes itself to the model as a single-parameter function' do
    # Arrange
    specialist = create_specialist(slug: 'auto')

    # Act
    schema = specialist.openai_schema

    # Assert
    expect(specialist.function_name).to eq('consultar_auto')
    expect(schema[:name]).to eq('consultar_auto')
    expect(schema[:description]).to eq('cotação de seguro de automóvel')
    expect(schema[:parameters][:properties].keys).to eq([described_class::REQUEST_PARAM])
    expect(schema[:parameters][:required]).to eq([described_class::REQUEST_PARAM])
    expect(schema[:strict]).to be(true)
  end

  it 'keeps the function name within the 64-char limit imposed by the model provider' do
    # Arrange
    specialist = create_specialist(name: 'a' * 90, slug: nil)

    # Assert
    expect(specialist.function_name.length).to be <= 64
    expect(specialist.slug).to match(described_class::SLUG_FORMAT)
  end

  it 'puts the system block before the account block in the effective instruction' do
    # Arrange
    specialist = create_specialist(slug: 'auto', custom_instruction: 'Fale como a Corretora X.')

    # Assert
    expect(specialist.effective_instruction)
      .to eq("Você cota seguro de automóvel.\n\nFale como a Corretora X.")
  end

  it 'falls back to the system block alone when the account wrote nothing' do
    expect(create_specialist(slug: 'auto').effective_instruction).to eq('Você cota seguro de automóvel.')
  end

  describe 'reserved tools' do
    let!(:quote_tool) do
      Autonomia::Agents::Tool.create!(
        account: account, agent: agent, name: 'Cotar', slug: 'cotar_auto',
        endpoint_url: 'https://adapters.example.com/quote', param_schema: []
      )
    end

    it 'resolves declared slugs in the declared order' do
      # Arrange
      Autonomia::Agents::Tool.create!(
        account: account, agent: agent, name: 'Placa', slug: 'buscar_placa',
        endpoint_url: 'https://adapters.example.com/plate', param_schema: []
      )
      specialist = create_specialist(slug: 'auto', tool_slugs: %w[buscar_placa cotar_auto])

      # Assert
      expect(specialist.tools.map(&:slug)).to eq(%w[buscar_placa cotar_auto])
    end

    it 'ignores a slug that no longer exists instead of breaking the turn' do
      specialist = create_specialist(slug: 'auto', tool_slugs: %w[cotar_auto ferramenta_apagada])
      expect(specialist.tools.map(&:slug)).to eq(['cotar_auto'])
    end

    it 'ignores a disabled tool' do
      quote_tool.update!(enabled: false)
      specialist = create_specialist(slug: 'auto', tool_slugs: %w[cotar_auto])
      expect(specialist.tools).to be_empty
    end

    it 'normalises blanks and duplicates on save' do
      specialist = create_specialist(slug: 'auto', tool_slugs: ['cotar_auto', ' cotar_auto ', '', nil])
      expect(specialist.tool_slugs).to eq(['cotar_auto'])
    end
  end

  it 'refuses more specialists than the per-agent limit' do
    # Arrange
    described_class::MAX_PER_AGENT.times { |i| create_specialist(slug: "ramo_#{i}") }

    # Act
    extra = described_class.new(agent: agent, name: 'Mais um', description: 'x', instruction: 'y', slug: 'extra')

    # Assert
    expect(extra.save).to be(false)
    expect(agent.specialists.count).to eq(described_class::MAX_PER_AGENT)
  end

  it 'refuses two specialists with the same slug on one agent' do
    create_specialist(slug: 'auto')
    expect { create_specialist(slug: 'auto') }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
