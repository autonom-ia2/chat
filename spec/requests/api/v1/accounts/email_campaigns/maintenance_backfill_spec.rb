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
end
