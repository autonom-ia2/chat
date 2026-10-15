require 'rails_helper'

# #1149 (R16): o painel pergunta onde a pessoa logada tem acesso restrito por funil, para não oferecer "Participar da
# conversa" onde a API recusaria (#1148).
RSpec.describe 'CRM meu acesso API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:restricted) { create(:user, account: account, role: :agent) }
  let(:free_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [restricted, free_agent].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: restricted, all_pipelines: false, triage: true)
    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: admin, all_pipelines: false, triage: true)
  end

  def meu_acesso(user)
    get "/api/v1/accounts/#{account.id}/crm/meu_acesso", headers: user.create_new_auth_token, as: :json
    response.parsed_body.dig('payload', 'restricted_inbox_ids')
  end

  it 'lists only the inboxes where the signed-in person is restricted' do
    expect(meu_acesso(restricted)).to eq([inbox.id])
    expect(response).to have_http_status(:ok)
  end

  it 'is empty for a person without restriction and for an administrator, even with an access row' do
    expect(meu_acesso(free_agent)).to eq([])
    expect(meu_acesso(admin)).to eq([])
  end

  it 'answers 404 when the CRM is off' do
    with_modified_env(CRM_KANBAN_ENABLED: 'false') do
      get "/api/v1/accounts/#{account.id}/crm/meu_acesso", headers: restricted.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:not_found)
  end
end
