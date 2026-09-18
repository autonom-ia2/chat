require 'rails_helper'

RSpec.describe 'Email protection maintenance request boundary', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/maintenance/backfills" }
  let(:input) { { reason: 'Approved synthetic preview', idempotency_key: 'boundary_436_01' } }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'false' do
      example.run
    end
  end

  it 'accepts unwrapped JSON from an authenticated actual platform administrator' do
    post path, params: input, headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:accepted)
    expect(EmailProtectionMaintenanceRun.sole).to have_attributes(account_id: account.id, dry_run: true, actor_id: actor.id)
  end

  it 'rejects account_id in the body even when it is identical to the routed account' do
    post path, params: input.merge(account_id: account.id), headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'unsupported_parameter')
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'rejects provider or kind in query parameters without hiding them behind the JSON body' do
    post "#{path}?provider=ses&kind=release", params: input, headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'serves status and retries a failed preview through the wired routes without applying' do
    headers = actor.create_new_auth_token
    post path, params: input, headers: headers, as: :json
    run = EmailProtectionMaintenanceRun.sole
    run.fail_run!('batch_failed')
    before = run.reload.attributes
    get "#{path}/#{run.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(run.reload.attributes).to eq(before)
    expect(response.parsed_body.keys).not_to include('actor_id', 'reason', 'idempotency_key', 'lease_token')
    post "#{path}/#{run.id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    expect(run.reload).to have_attributes(status: 'pending', dry_run: true, retry_count: 1)
    expect(EmailSuppressionEvent.count).to eq(0)
  end

  it 'denies all three routes to ordinary account administrators and unauthenticated requests' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: input)
    run.fail_run!('batch_failed')
    [{}, create(:user, account: account, role: :administrator).create_new_auth_token].each do |headers|
      post path, params: input, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      get "#{path}/#{run.id}", headers: headers
      expect(response).to have_http_status(:unauthorized)
      post "#{path}/#{run.id}/retry", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
    expect(run.reload).to have_attributes(status: 'failed', retry_count: 0)
    expect(EmailProtectionMaintenanceRun.count).to eq(1)
  end

  it 'does not disclose or retry a foreign run even to a SuperAdmin belonging to both accounts' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: actor)
    run = EmailCampaigns::Maintenance::Start.call(account: foreign, actor: actor, parameters: input)
    run.fail_run!('batch_failed')
    headers = actor.create_new_auth_token
    get "#{path}/#{run.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{path}/#{run.id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(run.reload).to have_attributes(status: 'failed', retry_count: 0)
  end

  it 'rechecks current account access on retry instead of trusting the original token' do
    headers = actor.create_new_auth_token
    post path, params: input, headers: headers, as: :json
    run = EmailProtectionMaintenanceRun.sole
    run.fail_run!('batch_failed')
    actor.account_users.where(account: account).delete_all
    post "#{path}/#{run.id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(run.reload.status).to eq('failed')
  end

  it 'rechecks the persisted SuperAdmin type on retry' do
    headers = actor.create_new_auth_token
    post path, params: input, headers: headers, as: :json
    run = EmailProtectionMaintenanceRun.sole
    run.fail_run!('batch_failed')
    actor.update!(type: nil)
    post "#{path}/#{run.id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(run.reload.retry_count).to eq(0)
  end

  it 'rejects missing or non-exact confirmation even when apply is enabled' do
    headers = actor.create_new_auth_token
    with_modified_env EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'true' do
      [nil, true, false, 'true', 'APPLY', 'apply '].each do |confirm|
        post path, params: input.merge(mode: 'apply', confirm: confirm), headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'invalid_confirm')
      end
      post path, params: input.merge(mode: 'apply'), headers: headers, as: :json
      expect(response.parsed_body).to eq('error' => 'invalid_confirm')
    end
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'rejects apply retry with its flag off without changing the run or dispatching' do
    headers = actor.create_new_auth_token
    with_modified_env EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'true' do
      post path, params: input.merge(mode: 'apply', confirm: 'apply'), headers: headers, as: :json
    end
    expect(response).to have_http_status(:accepted)
    run = EmailProtectionMaintenanceRun.sole
    run.fail_run!('apply_disabled')
    before = run.reload.attributes
    clear_enqueued_jobs
    post "#{path}/#{run.id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'apply_disabled')
    expect(run.reload.attributes).to eq(before)
    expect(enqueued_jobs).to be_empty
  end
end
