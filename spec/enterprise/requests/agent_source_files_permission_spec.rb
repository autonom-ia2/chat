require 'rails_helper'

RSpec.describe 'Agent source file permissions', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:permissions) { %w[autonomia_view] }
  let(:role) { create(:custom_role, account: account, permissions: permissions) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', status: :draft) }
  let(:source) { agent.sources.create!(account: account, source_type: 'txt', reference: 'guide.txt') }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources/#{source.id}/file" }
  let(:storage) { ActiveStorage::Blob.service }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!('custom_roles')
    user.account_users.find_by!(account: account).update!(custom_role: role)
    source.file.attach(io: StringIO.new('Example'), filename: 'guide.txt', content_type: 'text/plain')
    allow(storage).to receive(:exist?).and_return(true)
    allow(storage).to receive(:url).and_return('https://files.example.org/guide.txt')
  end

  it 'allows read-only module access without edit permission' do
    get url, headers: user.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(user.account_users.find_by!(account: account).permission_granted?('autonomia_manage')).to be(false)
  end

  context 'with edit permission' do
    let(:permissions) { %w[autonomia_manage] }

    it 'also permits reading the original file' do
      get url, headers: user.create_new_auth_token

      expect(response).to have_http_status(:ok)
    end
  end

  context 'with an unrelated permission' do
    let(:permissions) { %w[crm_view] }

    it 'denies the request without generating a link' do
      get url, headers: user.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
      expect(storage).not_to have_received(:url)
    end
  end
end
