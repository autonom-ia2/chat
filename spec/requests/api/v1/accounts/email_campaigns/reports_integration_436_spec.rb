require 'rails_helper'
require 'csv'

RSpec.describe 'Email campaign reports integration #436', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns" }
  let(:campaign) do
    create(:email_campaign, account: account, status: :paused, pause_reason: { kind: 'manual', code: 'manual_pause', note: 'private-note' })
  end
  let(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'unknown', preflight_reason_code: 'dns_disabled')
  end

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  it 'reads a public campaign DTO without collection or mutation and shares one protection presenter across a list' do
    recipient
    create(:email_campaign, account: account, sender_identity: campaign.sender_identity, status: :draft)
    expect(EmailCampaigns::Reputation::Metrics).not_to receive(:new)
    expect(EmailCampaigns::Reputation::Evaluator).not_to receive(:new)
    expect(EmailCampaigns::RecipientPreflightJob).not_to receive(:enqueue)
    expect(EmailCampaigns::Presentation::Protection).to receive(:new).once.and_call_original
    get "#{base}/campaigns", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch('payload').fetch('campaigns')
    row = rows.find { |item| item['id'] == campaign.id }
    expect(row).to include('status' => 'paused', 'pause_reason' => 'manual', 'name' => campaign.name, 'body_html' => campaign.body_html)
    expect(row.fetch('preflight')).to include('mode' => 'shadow', 'analysis_only' => true)
    expect(row.dig('protection', 'capabilities', 'resume')).to be(true)
    expect(response.body).not_to include('private-note', 'actor_id', 'provider_key', 'evaluation_generation')
    expect(campaign.reload.pause_reason).to include('note' => 'private-note')
    expect(EmailReputationState.where(account: account)).not_to exist
  end

  it 'whitelists list statuses and rejects malformed scalar shapes, conflicts and unsupported dates' do
    campaign
    create(:email_campaign, account: account, sender_identity: campaign.sender_identity, status: :draft)
    get "#{base}/campaigns", params: { status: 'attention', order: 'private', account: 'ignored' }, headers: headers, as: :json
    expect(response.parsed_body.fetch('payload').fetch('campaigns').pluck('id')).to eq([campaign.id])
    [{ status: 'bogus' }, { status: ['paused'] }, { q: { private: 'value' } }, { status: 'paused', campaign_status: 'draft' },
     { since: '2026-09-01' }, { until: '2026-09-17' }].each do |filters|
      get "#{base}/campaigns", params: filters, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'email_campaign.invalid_filter')
    end
    get "#{base}/campaigns", params: { since: '', until: '' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'reevaluates with the actual collector, leaves protection sticky, and resumes only on the explicit POST' do
    recipient
    create_list(:email_campaign_recipient, 50, email_campaign: campaign, status: :sent, sent_at: 1.hour.ago)
    state = EmailReputationState.create!(account: account, blocked: true, level: 'paused',
                                         trigger_snapshot: { code: 'reputation_threshold', note: 'private-trigger', actor_id: 987 })
    account.update!(internal_attributes: { email_campaigns_paused: { note: 'private-flag' } })
    post "#{base}/campaigns/#{campaign.id}/reevaluate", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload).to include('id' => campaign.id, 'status' => 'paused', 'pause_reason' => 'manual')
    expect(payload.fetch('protection')).to include('state' => 'paused', 'release_eligible' => true)
    expect(payload.dig('protection', 'capabilities', 'resume')).to be(true)
    state.reload
    generation = state.observation_generation
    expect(state.current_metrics['evaluation_generation']).to eq(generation)
    expect(generation).to be_positive
    expect(state).to be_blocked
    expect(response.body).not_to include('private-trigger', 'private-flag', 'actor_id', 'policy', 'evaluation_generation')

    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'status')).to eq('paused')
    expect(state.reload.observation_generation).to eq(generation)
    expect(state).to be_blocked

    post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload).to include('id' => campaign.id, 'status' => 'sending', 'pause_reason' => nil)
    expect(payload.fetch('protection')).to include('state' => 'healthy')
    expect(payload.dig('protection', 'capabilities', 'resume')).to be(false)
    expect(state.reload).not_to be_blocked
    expect(state.observation_generation).to be > generation
    expect(state.current_metrics['evaluation_generation']).to eq(state.observation_generation)
    expect(account.reload.internal_attributes).not_to have_key('email_campaigns_paused')
  end

  it 'uses fresh evidence after feedback instead of trusting eligibility supplied by the browser' do
    recipient
    rows = create_list(:email_campaign_recipient, 50, email_campaign: campaign, status: :sent, sent_at: 1.hour.ago)
    state = EmailReputationState.create!(account: account, blocked: true, level: 'paused')
    post "#{base}/campaigns/#{campaign.id}/reevaluate", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'protection', 'release_eligible')).to be(true)
    generation = state.reload.observation_generation
    rows.first.email_events.create!(event_type: :complaint, payload: { private: 'provider-diagnostic' })
    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'protection', 'release_eligible')).to be(false)
    post "#{base}/campaigns/#{campaign.id}/resume", params: { release_eligible: true, protection: { capabilities: { resume: true } } },
                                                    headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'email_campaign.protected')
    expect(response.parsed_body.fetch('protection')).to eq(
      'kind' => 'reputation', 'code' => 'reputation_paused', 'overridable' => false, 'resume_allowed' => false
    )
    expect(response.parsed_body.keys).to contain_exactly('error', 'protection')
    expect(response.body).not_to include(
      'provider-diagnostic', 'current_metrics', 'policy', 'trigger_snapshot', 'actor_id', 'override', 'private-note'
    )
    expect(campaign.reload).to be_paused
    expect(state.reload).to be_blocked
    expect(state.observation_generation).to be > generation
  end

  it 'invalidates an older published generation on GET without evaluating or writing' do
    recipient
    create_list(:email_campaign_recipient, 50, email_campaign: campaign, status: :sent, sent_at: 1.hour.ago)
    post "#{base}/campaigns/#{campaign.id}/reevaluate", headers: headers, as: :json
    state = EmailReputationState.find_by!(account: account)
    state.update!(observation_generation: state.observation_generation + 1)
    before_read = state.attributes
    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'protection', 'release_eligible')).to be(false)
    expect(state.reload.attributes).to eq(before_read)
  end

  it 'converts actual persisted ratios to public percentages without modifying the source metrics' do
    recipient
    counts = { sent: 200, permanent: 5, transient: 0, unknown: 0, complaints: 0, bounced: 5 }
    policy = EmailCampaigns::Reputation::Policy.new
    metrics = counts.merge(policy.evaluate(counts)).merge(evaluation_generation: 1)
    state = EmailReputationState.create!(account: account, current_metrics: metrics, policy: policy.snapshot,
                                         level: 'warning', evaluated_at: Time.current, observation_generation: 1)
    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'protection', 'current', 'hard_bounce_rate')).to eq(2.5)
    expect(state.reload.current_metrics['permanent_ratio']).to eq(0.025)
  end

  it 'resumes manual shadow pauses with DNS off and no SES sample, returning a fresh DTO' do
    recipient
    post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload).to include('id' => campaign.id, 'status' => 'sending', 'pause_reason' => nil)
    expect(payload.dig('protection', 'provider', 'state')).to eq('unknown')
    expect(payload.dig('protection', 'capabilities', 'resume')).to be(false)
    expect(payload.dig('preflight', 'counts', 'unknown')).to eq(1)
  end

  it 'enqueues the actual recheck, coalesces a live lease, and never resumes or claims completion' do
    recipient
    expect(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue).with(campaign.id, recheck: true).twice.and_call_original
    expect do
      post "#{base}/campaigns/#{campaign.id}/recheck", headers: headers, as: :json
    end.to have_enqueued_job(EmailCampaigns::RecipientPreflightJob).with(campaign.id, an_instance_of(String), 0)
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch('payload')).to include('id' => campaign.id, 'status' => 'paused', 'pause_reason' => 'manual')
    expect(response.parsed_body.dig('payload', 'preflight', 'status')).to eq('analysing')
    token = campaign.reload.preflight_lease_token
    expect(token).to be_present
    expect(campaign.preflight_summary).to include('rechecking' => true)
    expect(recipient.reload.preflight_status).to eq('unknown')
    expect do
      post "#{base}/campaigns/#{campaign.id}/recheck", headers: headers, as: :json
    end.not_to have_enqueued_job(EmailCampaigns::RecipientPreflightJob)
    expect(response).to have_http_status(:accepted)
    expect(campaign.reload.preflight_lease_token).to eq(token)
    expect(campaign).to be_paused
  end

  it 'denies recheck and resume during an active import' do
    recipient
    campaign.email_campaign_imports.create!(status: :processing)
    %w[recheck resume].each do |action|
      post "#{base}/campaigns/#{campaign.id}/#{action}", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(campaign.reload).to be_paused
      expect(campaign.preflight_lease_token).to be_nil
    end
  end

  %w[sent canceled failed].each do |status|
    it "rejects a recheck of a terminal #{status} campaign" do
      campaign.update!(status: status)
      post "#{base}/campaigns/#{campaign.id}/recheck", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(campaign.reload.status).to eq(status)
      expect(campaign.preflight_lease_token).to be_nil
    end
  end

  it 'does not advertise or execute resume for empty, fully suppressed or ambiguous campaigns' do
    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'protection', 'capabilities', 'resume')).to be(false)
    post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    EmailSuppression.create!(account: account, email: recipient.email, reason: 'unsubscribe')
    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'protection', 'capabilities', 'resume')).to be(false)
    post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    create(:email_campaign_recipient, email_campaign: campaign, ses_message_id: 'ambiguous-acceptance')
    post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(campaign.reload).to be_paused
  end

  it 'enforces actual preflight on resume and uses unknown rather than fake healthy provider telemetry' do
    recipient
    with_modified_env EMAIL_CAMPAIGN_HYGIENE_MODE: 'enforce' do
      post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      recipient.update!(preflight_status: 'valid', preflight_checked_at: Time.current, preflight_valid_until: 1.hour.from_now)
      post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'protection', 'provider', 'state')).to eq('unknown')
    end
  end

  it 'vetoes an SES provider block and preserves a direct-inbox manual resume' do
    recipient
    with_modified_env EMAIL_REPUTATION_PROVIDER_BLOCK: 'true' do
      post "#{base}/campaigns/#{campaign.id}/resume", headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('protection', 'code')).to eq('provider_manual_block')
      inbox = create(:inbox, :with_email, account: account)
      direct = create(:email_campaign, account: account, status: :paused, delivery_mode: :direct_inbox,
                                       sender_identity: nil, sender_inbox: inbox)
      create(:email_campaign_recipient, email_campaign: direct)
      post "#{base}/campaigns/#{direct.id}/resume", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'protection', 'provider', 'state')).to eq('not_applicable')
    end
  end

  %w[reevaluate recheck resume].each do |action|
    it "denies foreign campaigns and non-admin #{action} without side effects" do
      foreign = create(:email_campaign, status: :paused, name: 'private-campaign')
      post "#{base}/campaigns/#{foreign.id}/#{action}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('private-campaign')
      agent = create(:user, account: account, role: :agent)
      get '/api/v1/profile', headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('id')).to eq(agent.id)
      post "#{base}/campaigns/#{campaign.id}/#{action}", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
      expect(campaign.reload).to be_paused
      expect(EmailReputationState.where(account_id: [account.id, foreign.account_id])).not_to exist
    end
  end

  it 'returns bounded configuration errors without environment values or exception messages' do
    recipient
    [{ EMAIL_REPUTATION_MODE: 'private-config' }, { EMAIL_CAMPAIGN_HYGIENE_MODE: 'private-config' }].each do |env|
      with_modified_env env do
        get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'email_campaign.configuration_invalid')
        expect(response.body).not_to include('private-config', 'EMAIL_', 'ArgumentError')
      end
    end
  end

  it 'preserves legacy mutation payload fields and removes raw diagnostics and import internals' do
    campaign.update!(status: :sending, last_error: 'private-diagnostic', ai_error: 'private-ai')
    campaign.email_campaign_imports.create!(status: :failed, error_code: 'private-storage-key',
                                            result: { total: 2, imported: 1, actor_id: 987, note: 'private-import' })
    post "#{base}/campaigns/#{campaign.id}/pause", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload).to include('id' => campaign.id, 'status' => 'paused', 'pause_reason' => 'manual')
    expect(payload.keys).to include('subject', 'body_html', 'preflight', 'protection', 'last_error', 'ai_error', 'recipient_import')
    expect(payload.fetch('recipient_import')).to include('result' => { 'total' => 2, 'imported' => 1 }, 'error_code' => 'import_failed')
    expect(response.body).not_to include('private-', 'actor_id')
  end

  it 'routes import issues and their filtered CSV through the real query and tenant policy' do
    issue = campaign.email_campaign_import_issues.create!(row_number: 2, raw_address: ' =example.org', reason_code: 'invalid_email')
    campaign.email_campaign_import_issues.create!(row_number: 3, raw_address: 'excluded@example.org', reason_code: 'duplicate')
    get "#{base}/reports/#{campaign.id}/import_issues", params: { reason_code: 'invalid_email', q: '=example' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'issues').pluck('id')).to eq([issue.id])
    get "#{base}/reports/#{campaign.id}/import_issues/export", params: { reason: 'invalid_email', q: '=example', page: 2 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    rows = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
    expect(rows.size).to eq(1)
    expect(rows.first['raw_email']).to eq("' =example.org")
    get "#{base}/reports/#{campaign.id}/import_issues/export", params: { reason: ['duplicate'] }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.media_type).to eq('application/json')
    expect(response.headers['Content-Disposition']).to be_nil
  end

  %w[import_issues import_issues/export recipients export].each do |action|
    it "authorizes #{action} before producing any JSON or CSV for a different tenant" do
      foreign = create(:email_campaign)
      foreign.email_campaign_import_issues.create!(row_number: 1, raw_address: 'private@example.org', reason_code: 'duplicate')
      get "#{base}/reports/#{foreign.id}/#{action}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('private@example.org')
      agent = create(:user, account: account, role: :agent)
      get '/api/v1/profile', headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('id')).to eq(agent.id)
      get "#{base}/reports/#{campaign.id}/#{action}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
      expect(response.media_type).to eq('application/json')
      expect(response.headers['Content-Disposition']).to be_nil
    end
  end

  it 'uses the same strict recipient filters for paginated JSON and the unpaginated CSV' do
    rows = create_list(:email_campaign_recipient, 51, email_campaign: campaign, name: 'Literal %_ search', status: :failed)
    create(:email_campaign_recipient, email_campaign: campaign, name: 'Excluded', status: :failed)
    filters = { q: '%_', status: 'failed', problem: 'true', page: 2 }
    get "#{base}/reports/#{campaign.id}/recipients", params: filters, headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'recipients').pluck('id')).to eq([rows.last.id])
    get "#{base}/reports/#{campaign.id}/export", params: filters, headers: headers
    expect(response).to have_http_status(:ok)
    csv = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
    expect(csv.pluck('id').map(&:to_i)).to eq(rows.map(&:id))
    [{ status: 'nope' }, { page: 0 }, { problem: 'perhaps' }, { q: ['private'] }].each do |filter|
      get "#{base}/reports/#{campaign.id}/export", params: filter, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq('application/json')
      expect(response.headers['Content-Disposition']).to be_nil
    end
  end

  it 'keeps provider complaint prevention out of UI spam counters and presents the same protected statuses in JSON and CSV' do
    statuses = %i[sent suppressed unsubscribed complained]
    rows = EmailCampaigns::ComplaintClassifier::PREVENTED_SUBTYPES.flat_map do |subtype|
      statuses.map do |status|
        row = create(:email_campaign_recipient, email_campaign: campaign, status: status, sent_at: 1.hour.ago)
        row.email_events.create!(event_type: :complaint, occurred_at: 30.minutes.ago) if status == :complained
        2.times do
          row.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: subtype } })
        end
        row
      end
    end
    get "#{base}/reports", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload.fetch('summary')).to include('complained' => 2, 'provider_prevented' => 8, 'complaint_rate' => 25.0)
    expect(payload.fetch('campaigns').sole).to include('complained' => 2, 'provider_prevented' => 8, 'complaint_rate' => 25.0)
    expect(payload.dig('summary', 'activity', 'complaint')).to eq(18)
    get "#{base}/reports/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to include('complained' => 2, 'provider_prevented' => 8)

    get "#{base}/reports/#{campaign.id}/recipients", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    presented = response.parsed_body.dig('payload', 'recipients')
    expect(presented.pluck('id')).to eq(rows.map(&:id))
    expect(presented.pluck('status')).to eq(%w[suppressed suppressed unsubscribed complained] * 2)
    expect(presented.values_at(0, 1, 4, 5)).to all(include('delivery_outcome' => 'unknown', 'reason_code' => 'provider_suppression'))

    get "#{base}/reports/#{campaign.id}/export", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    csv = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
    expect(csv.pluck('id').map(&:to_i)).to eq(rows.map(&:id))
    expect(csv.pluck('status')).to eq(presented.pluck('status'))
    expect(csv.pluck('reason_code')).to eq(presented.pluck('reason_code'))
    expect(rows.map { |row| row.reload.status }).to eq(%w[sent suppressed unsubscribed complained] * 2)
  end

  it 'exposes delivery evidence in report metadata without presenting direct acceptance as confirmed delivery' do
    inbox = create(:inbox, :with_email, account: account)
    direct = create(:email_campaign, account: account, delivery_mode: :direct_inbox, sender_identity: nil, sender_inbox: inbox)
    row = create(:email_campaign_recipient, email_campaign: direct, status: :sent, sent_at: 1.hour.ago)
    row.email_events.create!(event_type: :delivered, payload: { via: 'direct_inbox' })
    ses_row = create(:email_campaign_recipient, email_campaign: campaign, status: :sent, sent_at: 1.hour.ago)
    ses_row.email_events.create!(event_type: :delivered, payload: { via: 'direct_inbox' })
    get "#{base}/reports", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'meta', 'delivery_evidence')).to include(
      'provider_confirmed' => 1, 'direct_acceptance_only' => 1, 'legacy_delivered_includes_acceptance' => true
    )
    expect(response.parsed_body.dig('payload', 'summary', 'delivered')).to eq(2)
    expect(response.parsed_body.dig('payload', 'campaigns')).to contain_exactly(
      include('id' => direct.id, 'delivery_mode' => 'direct_inbox', 'delivered' => 1),
      include('id' => campaign.id, 'delivery_mode' => 'ses', 'delivered' => 1)
    )
    get "#{base}/reports/#{direct.id}", headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'meta', 'delivery_evidence', 'provider_confirmed')).to eq(0)
    [direct, campaign].each do |source|
      get "#{base}/reports/#{source.id}", params: { delivery_mode: 'untrusted' }, headers: headers, as: :json
      expect(response.parsed_body.fetch('payload')).to include('delivery_mode' => source.delivery_mode, 'delivered' => 1)
      get "#{base}/reports/#{source.id}/recipients", params: { delivery_mode: 'untrusted' }, headers: headers, as: :json
      expect(response.parsed_body.dig('payload', 'meta', 'delivery_mode')).to eq(source.delivery_mode)
      expect(response.parsed_body.dig('payload', 'recipients')).to all(include('delivery_mode' => source.delivery_mode, 'status' => 'sent'))
      get "#{base}/reports/#{source.id}/timeline", headers: headers, as: :json
      expect(response.parsed_body.dig('payload', 'delivery_mode')).to eq(source.delivery_mode)
      expect(response.parsed_body.dig('payload', 'series').sum { |bucket| bucket['delivered'] }).to eq(1)
    end
    expect([row.reload.status, ses_row.reload.status]).to eq(%w[sent sent])
    get "#{base}/reports/#{direct.id}/recipients", params: { q: 'no-match' }, headers: headers, as: :json
    expect(response.parsed_body.dig('payload', 'recipients')).to eq([])
    expect(response.parsed_body.dig('payload', 'meta', 'delivery_mode')).to eq('direct_inbox')
    get "#{base}/reports", params: { since: '2026-09-01' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
