require 'rails_helper'

RSpec.describe Api::V1::Accounts::EmailCampaigns::MaintenanceController, type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:input) { { reason: 'Reviewed preview', idempotency_key: 'controller_436_01' } }
  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/maintenance/backfills" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'false' do
      example.run
    end
  end

  it 'allows an authenticated persisted SuperAdmin to create and read a dry run' do
    post path, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    run = EmailProtectionMaintenanceRun.sole
    expect(run).to be_dry_run
    get "#{path}/#{run.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => run.id, 'dry_run' => true)
  end

  it 'preserves the global 401 Pundit denial for ordinary account administrators' do
    ordinary_headers = create(:user, account: account, role: :administrator).create_new_auth_token
    get "/api/v1/accounts/#{account.id}", headers: ordinary_headers
    expect(response).to have_http_status(:ok)
    post path, params: input, headers: ordinary_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'denies unauthenticated access' do
    post path, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires the flag and the explicit apply mode together' do
    post path, params: input.merge(mode: 'apply', confirm: 'apply'), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'apply_disabled')
    with_modified_env EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'true' do
      post path, params: input.merge(mode: 'apply', confirm: 'apply'), headers: headers, as: :json
    end
    expect(response).to have_http_status(:accepted)
    expect(EmailProtectionMaintenanceRun.sole).not_to be_dry_run
  end

  it 'rejects role escalation and provider/kind parameters' do
    [{ actor_id: actor.id }, { role: 'SuperAdmin' }, { kind: 'release' }, { provider: 'ses' }].each do |extra|
      post path, params: input.merge(extra), headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'unsupported_parameter')
    end
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'returns 404 for a foreign run and GET never creates state' do
    post path, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    own_id = response.parsed_body.fetch('id')
    get "#{path}/#{own_id}", headers: headers
    expect(response).to have_http_status(:ok)
    foreign_account = create(:account)
    create(:account_user, account: foreign_account, user: actor)
    foreign = EmailCampaigns::Maintenance::Start.call(account: foreign_account, actor: actor, parameters: input)
    expect do
      get "#{path}/#{foreign.id}", headers: headers
    end.not_to change(EmailProtectionMaintenanceRun, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies read and retry to ordinary administrators, and does not advertise release capabilities' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: input)
    run.fail_run!('batch_failed')
    expect(run.public_progress.keys).not_to include('capabilities', 'actor_id', 'reason', 'idempotency_key', 'lease_token')
    ordinary_headers = create(:user, account: account, role: :administrator).create_new_auth_token
    get "/api/v1/accounts/#{account.id}", headers: ordinary_headers
    expect(response).to have_http_status(:ok)
    get "#{path}/#{run.id}", headers: ordinary_headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    post "#{path}/#{run.id}/retry", headers: ordinary_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    expect(run.reload.status).to eq('failed')
  end

  it 'rejects retry parameters and limits retry to the original actor in the routed tenant' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: input)
    run.fail_run!('batch_failed')
    post "#{path}/#{run.id}/retry", params: { mode: 'apply', confirm: 'apply' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'unsupported_parameter')
    other = create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin)
    other_headers = other.create_new_auth_token
    get "#{path}/#{run.id}", headers: other_headers
    expect(response).to have_http_status(:ok)
    post "#{path}/#{run.id}/retry", headers: other_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'actor_mismatch')
    expect(run.reload.status).to eq('failed')
  end
end
