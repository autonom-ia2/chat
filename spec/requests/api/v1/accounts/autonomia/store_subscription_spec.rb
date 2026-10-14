require 'rails_helper'

RSpec.describe 'Autonomia store subscription lifecycle', type: :request do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/autonomia_store/lifecycle.v1.json').read) }
  let(:capability) { fixture.fetch('cancellationCapability') }
  let(:account) { create(:account) }
  let(:user) { create(:super_admin) }
  let(:client) { instance_double(Autonomia::Financial::StoreLifecycleClient) }
  let(:subscription_id) { capability.dig('data', 'serviceSubscriptionId') }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/financial/store" }
  let(:path) { "#{base_path}/subscriptions/#{subscription_id}/cancellation" }
  let(:body) { { clientIntent: SecureRandom.uuid, expectedVersion: 1 } }

  before do
    create(:account_user, user: user, account: account, role: :administrator)
    allow(Autonomia::Sso::TokenStore).to receive(:authorization_token_for).and_return('fictitious-access')
    allow(Autonomia::Financial::StoreIdentity).to receive(:subject!).and_return(capability.dig('buyer', 'cognitoSub'))
    allow(Autonomia::Financial::StoreConfiguration).to receive(:new)
      .and_return(instance_double(Autonomia::Financial::StoreConfiguration, namespace: capability.fetch('namespace')))
    allow(Autonomia::Financial::StoreLifecycleClient).to receive(:new).and_return(client)
    allow(client).to receive(:cancellation!).with(subscription_id).and_return(capability)
  end

  it 'keeps the cancellation pilot restricted to superadmins' do
    admin = create(:user, :administrator, account: account)
    post path, params: body, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(Autonomia::Store::SubscriptionCommand.count).to eq(0)
    expect(Autonomia::Financial::StoreLifecycleClient).not_to have_received(:new)
  end

  it 'requires administrator membership even for a superadmin' do
    user.account_users.find_by!(account: account).update!(role: :agent)
    post path, params: body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unauthorized) # Existing module permission gate uses 401.
    expect(Autonomia::Store::SubscriptionCommand.count).to eq(0)
    expect(Autonomia::Financial::StoreLifecycleClient).not_to have_received(:new)
  end

  it 'persists the command and immutable version before queueing, without disabling a resource' do
    expect { post path, params: body, headers: auth_headers(user), as: :json }
      .to have_enqueued_job(Autonomia::Store::SubscriptionCommandJob)
    expect(response).to have_http_status(:accepted)
    record = Autonomia::Store::SubscriptionCommand.last
    expect(record).to have_attributes(state: 'pending', expected_version: 1, command_action: 'schedule', user_id: user.id)
    expect(record.financial_payload['idempotencyKey']).to eq(record.id)
    expect(Autonomia::Store::Activation.count).to eq(0)
  end

  it 'reuses an existing command without rechecking mutable capability or generating another key' do
    2.times { post path, params: body, headers: auth_headers(user), as: :json }
    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Store::SubscriptionCommand.count).to eq(1)
    expect(client).to have_received(:cancellation!).once
    command = Autonomia::Store::SubscriptionCommand.last
    command.update!(state: 'confirmed')
    capability['data']['canSchedule'] = false
    post path, params: body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.dig('data', 'state')).to eq('confirmed')
    expect(client).to have_received(:cancellation!).once
  end

  it 'rejects another body or intent while the original command is pending' do
    post path, params: body, headers: auth_headers(user), as: :json
    post path, params: body.merge(expectedVersion: 2), headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:conflict)
    post path, params: body.merge(clientIntent: SecureRandom.uuid), headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:conflict)
    expect(Autonomia::Store::SubscriptionCommand.count).to eq(1)
  end

  it 'rejects caller-provided policy, buyer and malformed versions before Financial' do
    [body.merge(policy: 'immediate'), body.merge(buyer: 'other'), body.merge(expectedVersion: '1')].each do |wrong|
      post path, params: wrong, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(client).not_to have_received(:cancellation!)
    expect(Autonomia::Store::SubscriptionCommand.count).to eq(0)
  end

  it 'does not invent paid-period eligibility or silently update an outdated version' do
    capability['data']['canSchedule'] = false
    post path, params: body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:conflict)
    capability['data']['canSchedule'] = true
    capability['data']['subscriptionVersion'] = 2
    post path, params: body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:conflict)
    expect(Autonomia::Store::SubscriptionCommand.count).to eq(0)
  end

  it 'allows an explicit reversal only when Financial says it is eligible' do
    capability['data']['canResume'] = true
    capability['data']['canSchedule'] = false
    post "#{path}/resume", params: body, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:accepted)
    expect(Autonomia::Store::SubscriptionCommand.last.command_action).to eq('resume')
  end

  it 'only resumes the original pending command owned by the current buyer' do
    post path, params: body, headers: auth_headers(user), as: :json
    command = Autonomia::Store::SubscriptionCommand.last
    post "#{base_path}/subscription-commands/#{command.id}/retry", headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:accepted)
    command.update!(buyer_subject: 'other-fictitious-buyer')
    get "#{base_path}/subscription-commands/#{command.id}", headers: auth_headers(user)
    expect(response).to have_http_status(:not_found)
  end
end
