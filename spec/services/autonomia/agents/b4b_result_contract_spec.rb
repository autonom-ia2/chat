require 'rails_helper'

RSpec.describe Autonomia::Agents::AnswerResult, 'B4b result contract', type: :service do
  let(:agent) do
    Autonomia::Agents::Agent.new(
      name: 'Clara', agent_type: 'custom', instruction: 'Atenda com clareza.'
    )
  end
  let(:result) do
    described_class.new(
      reply: 'Resposta segura',
      confidence: 0.9,
      handoff: { should: false, reason: nil },
      answered_from_knowledge: false,
      skipped_tools: [{ slug: 'atualiza_sistema', name: 'Atualiza sistema', code: 'viewer_not_allowed', args: { token: 'x' } }],
      writes_external: true
    )
  end

  it 'expõe os metadados de ferramenta, sem argumentos ou segredos' do
    payload = result.to_h

    expect(payload).to include(
      skipped_tools: [{ slug: 'atualiza_sistema', name: 'Atualiza sistema', code: 'viewer_not_allowed' }],
      writes_external: true
    )
    expect(payload.to_json).not_to include('token', 'args')
  end

  it 'mantém defaults seguros para respostas sem ferramenta' do
    plain = described_class.new(
      reply: 'Resposta', confidence: 0.9,
      handoff: { should: false, reason: nil }
    )

    expect(plain.to_h).to include(skipped_tools: [], writes_external: false)
  end

  it 'serializa os mesmos campos no Testar e no Sugerir' do
    allow(Autonomia::Agents::Config).to receive(:humanize_delivery_enabled?).and_return(false)

    test_json = ApplicationController.render(
      template: 'api/v1/accounts/autonomia/agents/playground/test',
      assigns: { agent: agent, result: result }, formats: [:json]
    )
    suggest_json = ApplicationController.render(
      template: 'api/v1/accounts/autonomia/agents/playground/suggest',
      assigns: { agent: agent, result: result }, formats: [:json]
    )

    [test_json, suggest_json].each do |raw|
      payload = JSON.parse(raw)
      expect(payload).to include(
        'skipped_tools' => [{ 'slug' => 'atualiza_sistema', 'name' => 'Atualiza sistema',
                              'code' => 'viewer_not_allowed' }],
        'writes_external' => true
      )
      expect(raw).not_to include('token', 'args')
    end
  end
end
