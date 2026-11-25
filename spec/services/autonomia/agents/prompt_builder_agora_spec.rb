require 'rails_helper'

# #3211 (P6): item `developer` "Agora: …" logo antes da pergunta, em todo agente menos a Lia, com chave de instalação.
RSpec.describe Autonomia::Agents::PromptBuilder do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end

  before { freeze_time }

  def textos_de(input)
    input.map { |item| item[:content].first[:text] }
  end

  it 'o item Agora vem logo antes da pergunta' do
    input = described_class.new(agent: agente, query: 'Tudo bem?').input

    expect(input[-2]).to eq(role: 'developer',
                            content: [{ type: 'input_text', text: Autonomia::Agents::PromptParts::Agora.texto(account) }])
    expect(input.last[:content].first[:text]).to eq('Tudo bem?')
  end

  it 'a Lia não recebe' do
    lia = Autonomia::Agents::Agent.new(account: account, agent_type: 'insurance_quote', name: 'Lia')

    expect(textos_de(described_class.new(agent: lia, query: 'oi').input)).not_to include(a_string_starting_with('Agora:'))
  end

  it 'com AI_AGENT_DATA_DO_TURNO=false, não entra' do
    with_modified_env(AI_AGENT_DATA_DO_TURNO: 'false') do
      expect(textos_de(described_class.new(agent: agente, query: 'oi').input)).not_to include(a_string_starting_with('Agora:'))
    end
  end

  it 'ausente a chave, entra' do
    expect(textos_de(described_class.new(agent: agente, query: 'oi').input)).to include(a_string_starting_with('Agora:'))
  end
end
