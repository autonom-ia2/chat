require 'rails_helper'

RSpec.describe 'CRM AI settings API', type: :request do
  around do |example|
    previous_crm = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_ai = ENV.fetch('CRM_AI_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV['CRM_AI_ENABLED'] = 'true'
    example.run
  ensure
    previous_crm.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_crm
    previous_ai.nil? ? ENV.delete('CRM_AI_ENABLED') : ENV['CRM_AI_ENABLED'] = previous_ai
  end

  it 'returns 404 when CRM AI is disabled' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    ENV['CRM_AI_ENABLED'] = 'false'

    get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
        headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('crm.ai.disabled')
  end

  it 'lets administrators read and update pipeline AI settings' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'enabled')).to eq(true)

    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: {
            ai_settings: {
              enabled: true,
              auto_move_enabled: true,
              stale_hours: 24
            },
            stage_criteria: {
              stage.id.to_s => 'Critério de teste'
            }
          },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'auto_move_enabled')).to eq(true)
    expect(stage.reload.metadata['ai_criteria']).to eq('Critério de teste')
  end

  it 'persists and returns the new handoff pool + escalation fields', :aggregate_failures do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    supervisor, = create_crm_agent(account: account, name: 'Supervisor')

    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: {
            ai_settings: {
              handoff: {
                enabled: true,
                handoff_mode: 'r3_invite',
                pool_type: 'user',
                pool_id: supervisor.id,
                escalation_action: 'escalate',
                escalation_user_id: supervisor.id,
                pickup_threshold_seconds: 600
              }
            }
          },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    handoff = response.parsed_body.dig('payload', 'handoff')
    expect(handoff['pool_type']).to eq('user')
    expect(handoff['pool_id']).to eq(supervisor.id)
    expect(handoff['escalation_action']).to eq('escalate')
    expect(handoff['selector_mode']).to eq(handoff['mode'])

    # partial PATCH (only trigger) must not drop the pool/escalation fields
    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: { ai_settings: { handoff: { trigger: 'Cliente pediu humano' } } },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    handoff = response.parsed_body.dig('payload', 'handoff')
    expect(handoff['trigger']).to eq('Cliente pediu humano')
    expect(handoff['pool_type']).to eq('user')
    expect(handoff['pool_id']).to eq(supervisor.id)
    expect(handoff['escalation_action']).to eq('escalate')
  end

  it 'keeps selector_mode mirroring mode across saves', :aggregate_failures do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)

    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: { ai_settings: { handoff: { enabled: true, mode: 'direct' } } },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    handoff = response.parsed_body.dig('payload', 'handoff')
    expect(handoff['mode']).to eq('direct')
    expect(handoff['selector_mode']).to eq('direct')

    # a partial PATCH of another field must not flip selector_mode to round_robin
    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: { ai_settings: { handoff: { trigger: 'Atendimento humano' } } },
          headers: auth_headers(admin)

    handoff = response.parsed_body.dig('payload', 'handoff')
    expect(handoff['mode']).to eq('direct')
    expect(handoff['selector_mode']).to eq('direct')
  end

  it 'round-trips the AI reminder mode and allowed days' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    path = "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings"
    patch path, params: { ai_settings: { auto_followup: { mode: 'ai_reminder', allowed_days: [1, 3, 5] } } },
                headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    get path, headers: auth_headers(admin)
    expect(response.parsed_body.dig('payload', 'auto_followup', 'mode')).to eq('ai_reminder')
    expect(response.parsed_body.dig('payload', 'auto_followup', 'allowed_days')).to eq([1, 3, 5])
  end

  it 'rejects empty weekdays and unknown modes without changing the configuration' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    path = "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings"
    original = pipeline.metadata.deep_dup
    [{ allowed_days: [] }, { mode: 'send_everything' }].each do |invalid|
      patch path, params: { ai_settings: { auto_followup: invalid } }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(pipeline.reload.metadata).to eq(original)
    end
  end

  it 'preserves legacy all-week schedules and defaults new pipelines to weekdays' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    expect(Crm::Ai::Config.auto_followup_settings(pipeline)[:allowed_days]).to eq([1, 2, 3, 4, 5])
    pipeline.update!(metadata: {})
    expect(Crm::Ai::Config.auto_followup_settings(pipeline)[:allowed_days]).to eq([0, 1, 2, 3, 4, 5, 6])
  end

  it 'disables a legacy schedule without validating or replacing its hidden fields' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    legacy = { 'enabled' => true, 'quiet_hours' => { 'start' => 8, 'end' => 8 }, 'intervals_hours' => [6, 72, 168] }
    pipeline.update!(metadata: { ai: { auto_followup: legacy } })
    path = "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings"
    patch path, params: { ai_settings: { auto_followup: { enabled: false, quiet_hours: { start: 2, end: 1 } } } },
                headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    saved = pipeline.reload.metadata.dig('ai', 'auto_followup')
    expect(saved['enabled']).to be(false)
    expect(saved['quiet_hours']).to eq(legacy['quiet_hours'])
    patch path, params: { ai_settings: { auto_followup: { enabled: true } } }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(pipeline.reload.metadata.dig('ai', 'auto_followup', 'enabled')).to be(false)
  end

  it 'rejects fractional hours instead of silently truncating them' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    original = pipeline.metadata.deep_dup
    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: { ai_settings: { auto_followup: { quiet_hours: { start: 8.5, end: 20.5 } } } },
          headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(pipeline.reload.metadata).to eq(original)
  end
end
