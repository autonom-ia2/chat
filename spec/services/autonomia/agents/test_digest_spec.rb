require 'rails_helper'

RSpec.describe Autonomia::Agents::TestDigest, type: :service do
  let(:snapshot_class) do
    Struct.new(
      :instrucao_do_sistema, :instruction, :name, :greeting, :fallback_message, :tone,
      :actuation, :handoff_rule, :handoff_strategy, :handoff_target_type, :handoff_target_id,
      :confidence_threshold, :audience, :audience_unknown_contact, :response_window,
      :agent_type, :mode, :voice, :avatar_url, :scaffold, :guardrails, :config, :ferramentas_nativas,
      keyword_init: true
    )
  end

  let(:agent) do
    snapshot_class.new(
      instrucao_do_sistema: 'Você atende com clareza.', instruction: 'coluna antiga',
      name: 'Clara', greeting: 'Olá', fallback_message: 'Vou verificar.', tone: 'acolhedor',
      actuation: 'external', handoff_rule: 'passe quando necessário', handoff_strategy: 'none',
      handoff_target_type: nil, handoff_target_id: nil, confidence_threshold: 0.7,
      audience: {}, audience_unknown_contact: 'respond', response_window: 'always',
      agent_type: 'support', mode: 'guided', voice: 'neutral', avatar_url: '/avatars/clara.png',
      scaffold: 'base scaffold',
      guardrails: ['não invente'], config: { 'with_knowledge' => true }
    )
  end
  let(:material_digest_a) { "sha256:#{'c' * 64}" }
  let(:material_projection) do
    {
      material_snapshot_digest: material_digest_a,
      material_snapshot_state: 'complete',
      source_ids: [11, 12],
      source_fingerprints: { 11 => 'fp-first', 12 => 'fp-second' },
      knowledge_entry_updated_at: '2026-10-07T10:05:00Z',
      with_knowledge_effective: true
    }
  end
  let(:tools) do
    [
      { id: 2, slug: 'consultar_cep', enabled: true, updated_at: '2026-10-07T09:00:00Z' },
      { id: 1, slug: 'consultar_produtos_cotacao', enabled: false, updated_at: '2026-10-07T08:00:00Z' }
    ]
  end
  let(:operation_config) do
    {
      'voice_reply' => false,
      'voice_instructions' => 'não exponha esta instrução privada',
      'humanize_delivery' => true,
      'operate_media' => false,
      'operate_reactions' => false,
      'test_allowlist_phones' => ['+5511999999999'],
      'silence_tokens' => ['SEGREDO_SILENCIO'],
      'native_tool_slugs' => ['consultar_cep'],
      'debounce_seconds' => 2,
      'async_tools' => true,
      'async_poll_intervals' => [2, 3, 10],
      'async_deadline_seconds' => 60
    }
  end
  let(:digest) do
    described_class.new(
      agent: agent,
      material_projection: material_projection,
      tools: tools,
      operation_config: operation_config
    ).call
  end

  def digest_for(agent: self.agent, material: material_projection, config: operation_config, tool_rows: tools)
    described_class.new(
      agent: agent, material_projection: material, tools: tool_rows, operation_config: config
    ).call
  end

  it 'is deterministic and canonicalizes tool order without persisting source text' do
    reordered = tools.reverse

    expect(digest_for).to eq(digest_for(tool_rows: reordered))
    expect(digest).to include(
      tested_digest: start_with('sha256:'), person_digest: start_with('sha256:')
    )
    expect(digest.fetch(:tested_digest).length).to eq(7 + 64)
    expect(digest.fetch(:person_digest).length).to eq(7 + 64)
    expect(digest).to include(material_snapshot_digest: material_digest_a, material_snapshot_state: 'complete')
    expect(digest.fetch(:components).keys).to include(
      :instruction_effective_digest, :tools_digest, :material_snapshot_digest,
      :operational_config_digest, :with_knowledge_effective
    )
    expect(digest.to_json).not_to include('Você atende com clareza', 'SEGREDO_SILENCIO', '+5511999999999')
  end

  it 'includes the effective instruction and person-facing fields that change behavior' do
    changed_person = digest_for(agent: agent.dup.tap { |copy| copy.name = 'Lia' })

    expect(digest_for(agent: agent.dup.tap { |copy| copy.instrucao_do_sistema = 'nova instrução' }))
      .not_to eq(digest)
    expect(changed_person).not_to eq(digest)
    expect(changed_person.fetch(:person_digest)).not_to eq(digest.fetch(:person_digest))
    expect(digest_for(agent: agent.dup.tap { |copy| copy.greeting = 'Bom dia' })).not_to eq(digest)
    expect(digest_for(agent: agent.dup.tap { |copy| copy.scaffold = 'outro scaffold' })).not_to eq(digest)
    expect(digest_for(agent: agent.dup.tap { |copy| copy.instruction = 'mudança que Lia não lê' }))
      .to eq(digest)
  end

  it 'changes when the effective material or knowledge choice changes' do
    changed_material = material_projection.merge(
      material_snapshot_digest: "sha256:#{'e' * 64}",
      source_ids: [12, 13]
    )
    changed_knowledge = agent.dup.tap { |copy| copy.config = { 'with_knowledge' => false } }

    changed_material_digest = digest_for(material: changed_material)
    expect(changed_material_digest).not_to eq(digest)
    expect(changed_material_digest.fetch(:person_digest)).to eq(digest.fetch(:person_digest))
    expect(changed_material_digest.fetch(:tested_digest)).not_to eq(digest.fetch(:tested_digest))
    expect(digest_for(agent: changed_knowledge)).not_to eq(digest)
  end

  it 'changes for every closed operational key while leaving raw values out of the result' do
    changed_values = {
      'voice_reply' => true,
      'voice_instructions' => 'outra instrução privada',
      'humanize_delivery' => false,
      'operate_media' => true,
      'operate_reactions' => true,
      'test_allowlist_phones' => ['+5511888888888'],
      'silence_tokens' => ['OUTRO_SILENCIO'],
      'native_tool_slugs' => ['consultar_produtos_cotacao'],
      'debounce_seconds' => 3,
      'async_tools' => false,
      'async_poll_intervals' => [2, 5, 12],
      'async_deadline_seconds' => 61
    }

    Autonomia::Agents::ConfigContract::OPERATIONAL_KEYS.each do |key|
      changed = operation_config.dup
      changed[key] = changed_values.fetch(key)

      expect(digest_for(config: changed)).not_to eq(digest), "expected #{key} to affect the digest"
    end

    expect(digest.to_json).not_to include('não exponha esta instrução privada', 'OUTRO_SILENCIO')
  end

  it 'changes for tool identity, enabled state and version but ignores client text and media' do
    changed_tool = tools.map { |tool| tool.merge(updated_at: '2026-10-08T09:00:00Z') }
    changed_enabled = tools.map { |tool| tool.merge(enabled: !tool[:enabled]) }

    expect(digest_for(tool_rows: changed_tool)).not_to eq(digest)
    expect(digest_for(tool_rows: changed_enabled)).not_to eq(digest)
    expect(digest_for(agent: agent.dup.tap { |copy| copy.avatar_url = '/avatars/clara-new.png' }))
      .to eq(digest)
    expect(digest_for(material: material_projection.merge(client_text: 'texto do cliente', images: ['data:image/png;base64,secret'])))
      .to eq(digest)
  end

  it 'uses the effective native registry vector without persisting credentials' do
    native_agent = agent.dup.tap do |copy|
      copy.config = copy.config.merge('native_tool_slugs' => ['consultar_cep'])
      copy.ferramentas_nativas = ['consultar_cep']
    end
    native_tool = Struct.new(:slug, :name, :endpoint_url, :token).new(
      'consultar_cep', 'Consultar CEP', 'https://private.example/lookup', 'native-secret'
    )
    allow(Autonomia::Agents::Tools::Registry).to receive(:for_agent).with(native_agent).and_return([native_tool])

    available = described_class.for_agent(agent: native_agent, material_projection: material_projection, tools: [])

    allow(Autonomia::Agents::Tools::Registry).to receive(:for_agent).with(native_agent).and_return([])
    unavailable = described_class.for_agent(agent: native_agent, material_projection: material_projection, tools: [])

    expect(available.fetch(:components).fetch(:tools_digest)).not_to eq(unavailable.fetch(:components).fetch(:tools_digest))
    expect(available.fetch(:tested_digest)).not_to eq(unavailable.fetch(:tested_digest))
    expect(available.to_json).not_to include('private.example', 'native-secret')
    expect(Autonomia::Agents::Tools::Registry).to have_received(:for_agent).with(native_agent).twice
  end

  it 'reuses effective runtime normalization for silence, confidence and voice' do
    baseline_agent = agent.dup.tap do |copy|
      copy.config = copy.config.merge('confidence_threshold' => '1.0', 'voice' => 'feminina')
    end
    equivalent_agent = agent.dup.tap do |copy|
      copy.config = copy.config.merge('confidence_threshold' => '2.0', 'voice' => ' FEMININA ')
    end
    baseline_config = operation_config.merge('silence_tokens' => ['conversation_closed_for_now'])
    equivalent_config = operation_config.merge('silence_tokens' => [' ** Conversation_Closed_For_Now ** '])

    baseline = digest_for(agent: baseline_agent, config: baseline_config)
    equivalent = digest_for(agent: equivalent_agent, config: equivalent_config)

    expect(Autonomia::Agents::Config.voice_for(baseline_agent)).to eq('marin')
    expect(Autonomia::Agents::Config.voice_for(equivalent_agent)).to eq('marin')
    expect(equivalent).to eq(baseline)

    changed = digest_for(
      agent: equivalent_agent.dup.tap { |copy| copy.config = copy.config.merge('confidence_threshold' => '0.8') },
      config: equivalent_config.merge('silence_tokens' => ['outra_resposta'])
    )
    expect(changed).not_to eq(baseline)
  end
end
