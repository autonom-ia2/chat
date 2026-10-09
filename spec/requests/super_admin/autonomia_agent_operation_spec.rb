require 'rails_helper'

RSpec.describe 'Super Admin Autonomia agent operation config', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let(:operation_cases) do
    slugs = Autonomia::Agents::Tools::Registry.slugs

    {
      'voice_reply' => { set: true, replace: false, clear: nil },
      'voice_instructions' => { set: 'Fale pausado.', replace: 'Fale objetivo.', clear: '' },
      'humanize_delivery' => { set: false, replace: true, clear: nil },
      'operate_media' => { set: false, replace: true, clear: nil },
      'operate_reactions' => { set: false, replace: true, clear: nil },
      'test_allowlist_phones' => {
        set: ['+5511999999999'], replace: ['+5511888888888'], clear: []
      },
      'silence_tokens' => { set: ['custom_silence'], replace: ['other_silence'], clear: [] },
      'native_tool_slugs' => { set: [slugs.first], replace: [slugs.last], clear: [] },
      'debounce_seconds' => { set: 10, replace: 12, clear: nil },
      'async_tools' => { set: false, replace: true, clear: nil },
      'async_poll_intervals' => { set: [3, 8], replace: [5, 13], clear: [] },
      'async_deadline_seconds' => { set: 120, replace: 240, clear: nil }
    }
  end
  let!(:account) { create(:account) }
  let!(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account,
      name: 'Agente operacional',
      agent_type: 'custom',
      instruction: 'Atenda com clareza.',
      config: { 'existing_setting' => 'preserve' }
    )
  end
  let!(:neighbor) do
    Autonomia::Agents::Agent.create!(
      account: account,
      name: 'Agente vizinho',
      agent_type: 'custom',
      config: { 'voice_reply' => false }
    )
  end
  let(:url) { "/super_admin/accounts/#{account.id}/agents/#{agent.id}/operation_config" }

  before { sign_in(super_admin, scope: :super_admin) }

  around do |example|
    with_modified_env(
      AI_AGENT_VOICE_REPLY: 'false',
      AI_HUMANIZE_DELIVERY: 'true',
      AI_AGENT_MEDIA: 'true',
      AI_AGENT_REACTIONS: 'true',
      AI_AGENT_ASYNC_TOOLS: 'true'
    ) do
      example.run
    end
  end

  def patch_operation(config, operation_url: url)
    patch operation_url, params: { operation_config: config }, as: :json
  end

  # This table intentionally exercises every existing reader behind the single
  # operational contract; splitting it would hide the cross-reader coverage.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def expect_reader_value(key, value)
    current_agent = agent.reload

    case key
    when 'voice_reply'
      expect(Autonomia::Agents::Config.voice_reply_enabled?(current_agent)).to eq(value.nil? ? false : value)
    when 'voice_instructions'
      expected = value.to_s.strip.presence || Autonomia::Agents::Config::DEFAULT_VOICE_INSTRUCTIONS
      expect(Autonomia::Agents::Config.voice_instructions_for(current_agent)).to eq(expected)
    when 'humanize_delivery'
      expect(Autonomia::Agents::Config.humanize_delivery_enabled?(current_agent)).to eq(value.nil? || value)
    when 'operate_media'
      expect(Autonomia::Agents::Config.operate_media_enabled?(current_agent)).to eq(value.nil? || value)
    when 'operate_reactions'
      expect(Autonomia::Agents::Config.operate_reactions_enabled?(current_agent)).to eq(value.nil? || value)
    when 'test_allowlist_phones'
      phone = Array(value).first || '+5511000000000'
      contact = Struct.new(:phone_number).new(phone)
      conversation = Struct.new(:contact).new(contact)
      expect(Autonomia::Agents::Operate.test_allowlist_permits?(conversation, current_agent)).to be(true)
    when 'silence_tokens'
      inbox = instance_double(Autonomia::Agents::AgentInbox, agent: current_agent)
      responder = Autonomia::Agents::Operate::Responder.new(conversation: nil, agent_inbox: inbox)
      expected = Array(value).filter_map { |token| token.to_s.strip.downcase.presence }
      expected = [Autonomia::Agents::Operate::Responder::SILENCE_TOKEN] if expected.empty?
      expect(responder.send(:silence_tokens)).to eq(expected)
    when 'native_tool_slugs'
      expect(Array(current_agent.ferramentas_nativas)).to eq(Array(value))
    when 'debounce_seconds'
      expected = value.nil? ? Autonomia::Agents::Config::OPERATE_DEBOUNCE_SECONDS : value.seconds
      expect(Autonomia::Agents::Config.debounce_seconds_for(current_agent)).to eq(expected)
    when 'async_tools'
      expect(Autonomia::Agents::Tools::AsyncConfig.enabled?(current_agent)).to eq(value.nil? || value)
    when 'async_poll_intervals'
      expected = Array(value).presence&.map(&:to_f) || Autonomia::Agents::Tools::AsyncConfig::DEFAULT_INTERVALS
      expect(Autonomia::Agents::Tools::AsyncConfig.intervals_for(current_agent)).to eq(expected)
    when 'async_deadline_seconds'
      expected = value.nil? ? Autonomia::Agents::Tools::AsyncConfig::DEFAULT_DEADLINE_SECONDS.seconds : value.seconds
      expect(Autonomia::Agents::Tools::AsyncConfig.deadline_seconds_for(current_agent)).to eq(expected)
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  it 'sets, replaces and clears every operational key through the dedicated route', :aggregate_failures do
    operation_cases.each do |key, values|
      patch_operation({ key => values[:set] })
      expect(response).to have_http_status(:success)
      expect(agent.reload.config[key]).to eq(values[:set])
      expect_reader_value(key, values[:set])

      patch_operation({ key => values[:replace] })
      expect(response).to have_http_status(:success)
      expect(agent.reload.config[key]).to eq(values[:replace])
      expect_reader_value(key, values[:replace])

      patch_operation({ key => values[:clear] })
      expect(response).to have_http_status(:success)
      if values[:clear].nil?
        expect(agent.reload.config).not_to have_key(key)
      else
        expect(agent.reload.config[key]).to eq(values[:clear])
      end
      expect_reader_value(key, values[:clear])

      # `null` is also an explicit remove for every operational key, including keys whose
      # reader has the more specific []/"" reset semantics above.
      patch_operation({ key => nil })
      expect(response).to have_http_status(:success)
      expect(agent.reload.config).not_to have_key(key)
      expect_reader_value(key, nil)
    end

    expect(agent.reload.config['existing_setting']).to eq('preserve')
    expect(neighbor.reload.config).to eq('voice_reply' => false)
  end

  it 'records a sanitized update with the SuperAdmin actor and the stable action' do
    raw_phone = '+5511999999999'

    patch_operation({ 'test_allowlist_phones' => [raw_phone] })

    expect(response).to have_http_status(:success)
    audit = Audited.audit_class.where(auditable: agent, action: 'update').order(:created_at, :id).last
    expect(audit).to have_attributes(
      auditable_type: 'Autonomia::Agents::Agent',
      associated_type: 'Account',
      associated_id: account.id,
      user_type: 'SuperAdmin',
      user_id: super_admin.id,
      username: super_admin.email,
      action: 'update',
      created_at: be_present
    )
    operation_change = audit.audited_changes.fetch('operation_config').fetch('test_allowlist_phones')
    expect(operation_change).to include('old', 'new')
    expect(operation_change.to_json).not_to include(raw_phone)
    expect(audit.audited_changes.to_json).not_to include(agent.instruction)
    expect(audit.audited_changes.to_json).not_to include(agent.scaffold) if agent.scaffold.present?
  end

  it 'rolls back the agent write when the audit cannot be persisted' do
    before_config = agent.reload.config
    before_audit_count = Audited.audit_class.where(auditable: agent, action: 'update').count
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'audit unavailable')

    patch_operation({ 'voice_reply' => true })

    expect(response).to have_http_status(:internal_server_error)
    expect(Audited.audit_class).to have_received(:create!).once
    expect(agent.reload.config).to eq(before_config)
    expect(Audited.audit_class.where(auditable: agent, action: 'update').count).to eq(before_audit_count)
  end

  it 'keeps a present nil key distinguishable from an absent key and redacts invalid old blobs' do
    agent.update!(config: {
                    'voice_reply' => nil,
                    'voice_instructions' => 'texto antigo que não deve aparecer',
                    'native_tool_slugs' => { 'raw' => 'valor legado' },
                    'async_poll_intervals' => { 'raw' => 'valor legado' }
                  })

    patch_operation({
                      'voice_reply' => nil,
                      'voice_instructions' => 'Nova instrução.',
                      'native_tool_slugs' => [],
                      'async_poll_intervals' => []
                    })

    expect(response).to have_http_status(:success)
    audit = Audited.audit_class.where(auditable: agent, action: 'update').order(:created_at, :id).last
    changes = audit.audited_changes.fetch('operation_config')
    expect(changes.fetch('voice_reply')).to include('old', 'new')
    expect(changes.fetch('voice_instructions')).to eq(
      'old' => { 'length' => 'texto antigo que não deve aparecer'.length },
      'new' => { 'length' => 'Nova instrução.'.length }
    )
    expect(changes.fetch('native_tool_slugs')).to eq(
      'old' => { 'redacted' => true },
      'new' => { 'count' => 0 }
    )
    expect(changes.fetch('async_poll_intervals')).to eq(
      'old' => { 'redacted' => true },
      'new' => { 'count' => 0, 'min' => nil, 'max' => nil }
    )
    expect(audit.audited_changes.to_json).not_to include('valor legado', 'texto antigo que não deve aparecer')
  end

  %w[
    voice_reply
    voice_instructions
    humanize_delivery
    operate_media
    operate_reactions
    test_allowlist_phones
    silence_tokens
    native_tool_slugs
    debounce_seconds
    async_tools
    async_poll_intervals
    async_deadline_seconds
  ].each do |key|
    it "rejects an invalid raw value for #{key} before the lock" do
      invalid_value = case key
                      when 'voice_reply', 'humanize_delivery', 'operate_media', 'operate_reactions', 'async_tools'
                        'true'
                      when 'voice_instructions'
                        'a' * 6_001
                      when 'test_allowlist_phones'
                        ['5511999999999']
                      when 'silence_tokens'
                        ['']
                      when 'native_tool_slugs'
                        ['unknown_native_tool']
                      when 'debounce_seconds'
                        31
                      when 'async_poll_intervals'
                        [1]
                      when 'async_deadline_seconds'
                        29
                      end
      before_config = agent.reload.config

      patch_operation({ key => invalid_value })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'operation_value_not_allowed', 'key' => key)
      expect(agent.reload.config).to eq(before_config)
    end
  end

  # This example intentionally checks every body-level rejection without allowing
  # any of those requests to reach the writer.
  # rubocop:disable RSpec/MultipleExpectations
  it 'rejects sibling fields and unknown operation keys before strong params' do
    before_config = agent.reload.config

    patch_operation({ 'voice_reply' => true, 'unknown_key' => false })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => 'unknown_key')
    expect(agent.reload.config).to eq(before_config)

    patch_operation({ 'agent_id' => agent.id })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => 'agent_id')
    expect(agent.reload.config).to eq(before_config)

    patch url, params: { operation_config: { 'voice_reply' => true }, sibling: { 'ignored' => true } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => 'sibling')
    expect(agent.reload.config).to eq(before_config)

    patch url, params: { operation_config: { 'voice_reply' => true }, account: { 'id' => account.id } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed', 'key' => 'account')
    expect(agent.reload.config).to eq(before_config)

    patch "#{url}?operation_config%5Bvoice_reply%5D=true", params: {}, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'config_key_not_allowed')
    expect(agent.reload.config).to eq(before_config)
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'redirects an unauthenticated HTML request' do
    sign_out(:super_admin)
    patch url, params: { operation_config: { 'voice_reply' => true } }
    expect(response).to have_http_status(:redirect)
    expect(agent.reload.config).not_to have_key('voice_reply')
  end

  it 'returns unauthorized for an unauthenticated JSON request' do
    sign_out(:super_admin)
    patch url, params: { operation_config: { 'voice_reply' => true } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(agent.reload.config).not_to have_key('voice_reply')
  end

  it 'returns unauthorized for a normal account user using JSON' do
    sign_out(:super_admin)
    account_user = create(:user, account: account, role: :administrator)
    sign_in(account_user, scope: :user)
    patch url, params: { operation_config: { 'voice_reply' => true } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(agent.reload.config).not_to have_key('voice_reply')
  end

  it 'rejects a foreign agent and keeps the selected account isolated' do
    other_account = create(:account)
    foreign_agent = Autonomia::Agents::Agent.create!(
      account: other_account, name: 'Agente estrangeiro', agent_type: 'custom', config: { 'voice_reply' => false }
    )
    before_config = foreign_agent.config
    foreign_url = "/super_admin/accounts/#{account.id}/agents/#{foreign_agent.id}/operation_config"

    patch_operation({ 'voice_reply' => true }, operation_url: foreign_url)

    expect(response).to have_http_status(:not_found)
    expect(foreign_agent.reload.config).to eq(before_config)
    expect(neighbor.reload.config).to eq('voice_reply' => false)
  end

  it 'does not expose or mutate system agents' do
    system_agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Guia', agent_type: 'custom', config: { 'system_key' => 'guia' }
    )
    system_url = "/super_admin/accounts/#{account.id}/agents/#{system_agent.id}/operation_config"
    system_config = system_agent.config

    patch_operation({ 'voice_reply' => true }, operation_url: system_url)

    expect(response).to have_http_status(:not_found)
    expect(system_agent.reload.config).to eq(system_config)
  end

  it 'does not offer native tools for Lia' do
    lia = Autonomia::Agents::Agent.create!(
      account: account, name: 'Lia', agent_type: 'insurance_quote', config: {}
    )
    lia_url = "/super_admin/accounts/#{account.id}/agents/#{lia.id}/operation_config"

    patch_operation({ 'native_tool_slugs' => [Autonomia::Agents::Tools::Registry.slugs.first] }, operation_url: lia_url)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'operation_value_not_allowed', 'key' => 'native_tool_slugs')
    expect(lia.reload.config).to eq({})
  end

  it 'omits deploy-maintained native tools from Lia responses while preserving them in storage' do
    native_slugs = [Autonomia::Agents::Tools::Registry.slugs.first]
    lia = Autonomia::Agents::Agent.create!(
      account: account, name: 'Lia', agent_type: 'insurance_quote', config: { 'native_tool_slugs' => native_slugs }
    )
    lia_url = "/super_admin/accounts/#{account.id}/agents/#{lia.id}/operation_config"

    patch_operation({ 'voice_reply' => false }, operation_url: lia_url)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('operation_config')).to include('voice_reply' => false)
    expect(response.parsed_body.fetch('operation_config')).not_to have_key('native_tool_slugs')
    expect(lia.reload.config.fetch('native_tool_slugs')).to eq(native_slugs)
  end
end
