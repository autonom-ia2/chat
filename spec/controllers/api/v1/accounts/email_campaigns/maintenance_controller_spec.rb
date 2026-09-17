require 'rails_helper'

RSpec.describe Api::V1::Accounts::EmailCampaigns::MaintenanceController, type: :controller do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:input) { { reason: 'Reviewed preview', idempotency_key: 'controller_436_01' } }

  before do
    sign_in(actor, scope: :user)
  end

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'false' do
      example.run
    end
  end

  it 'allows an authenticated persisted SuperAdmin to create and read a dry run' do
    post :create, params: { account_id: account.id }.merge(input), format: :json
    expect(response).to have_http_status(:accepted)
    run = EmailProtectionMaintenanceRun.sole
    expect(run).to be_dry_run
    get :show, params: { account_id: account.id, id: run.id }, format: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => run.id, 'dry_run' => true)
  end

  it 'preserves the global 401 Pundit denial for ordinary account administrators' do
    sign_in(create(:user, account: account, role: :administrator))
    post :create, params: { account_id: account.id }.merge(input), format: :json
    expect(response).to have_http_status(:unauthorized)
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'denies unauthenticated access' do
    sign_out(actor)
    post :create, params: { account_id: account.id }.merge(input), format: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires the flag and the explicit apply mode together' do
    post :create, params: { account_id: account.id }.merge(input, mode: 'apply', confirm: 'apply'), format: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'apply_disabled')
    with_modified_env EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'true' do
      post :create, params: { account_id: account.id }.merge(input, mode: 'apply', confirm: 'apply'), format: :json
    end
    expect(response).to have_http_status(:accepted)
    expect(EmailProtectionMaintenanceRun.sole).not_to be_dry_run
  end

  it 'rejects role escalation and provider/kind parameters' do
    [{ actor_id: actor.id }, { role: 'SuperAdmin' }, { kind: 'release' }, { provider: 'ses' }].each do |extra|
      post :create, params: { account_id: account.id }.merge(input).merge(extra), format: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'returns 404 for a foreign run and GET never creates state' do
    foreign_account = create(:account)
    create(:account_user, account: foreign_account, user: actor)
    foreign = EmailCampaigns::Maintenance::Start.call(account: foreign_account, actor: actor, parameters: input)
    expect do
      get :show, params: { account_id: account.id, id: foreign.id }, format: :json
    end.not_to change(EmailProtectionMaintenanceRun, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies read and retry to ordinary administrators, and does not advertise release capabilities' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: input)
    run.fail_run!('batch_failed')
    expect(run.public_progress.keys).not_to include('capabilities', 'actor_id', 'reason', 'idempotency_key', 'lease_token')
    sign_in(create(:user, account: account, role: :administrator))
    get :show, params: { account_id: account.id, id: run.id }, format: :json
    expect(response).to have_http_status(:unauthorized)
    post :retry, params: { account_id: account.id, id: run.id }, format: :json
    expect(response).to have_http_status(:unauthorized)
    expect(run.reload.status).to eq('failed')
  end

  it 'rejects retry parameters and limits retry to the original actor in the routed tenant' do
    run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: input)
    run.fail_run!('batch_failed')
    post :retry, params: { account_id: account.id, id: run.id, mode: 'apply', confirm: 'apply' }, format: :json
    expect(response.parsed_body).to eq('error' => 'unsupported_parameter')
    other = create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin)
    sign_in(other, scope: :user)
    post :retry, params: { account_id: account.id, id: run.id }, format: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'actor_mismatch')
    expect(run.reload.status).to eq('failed')
  end
end
