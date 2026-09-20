require 'rails_helper'

RSpec.describe 'CRM Kanban AI integration hook API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:params) { { app_id: 'crm_kanban_ai', settings: { api_key: 'sk-valida' } } }

  before { allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true) }

  it 'connects the key with the AI already on, and never sends the key back' do
    post api_v1_account_integrations_hooks_url(account_id: account.id),
         params: params,
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['settings']).to eq('enabled' => true)
    expect(response.body).not_to include('sk-valida')
    expect(account.hooks.find_by(app_id: 'crm_kanban_ai').settings['api_key']).to eq('sk-valida')
  end

  it 'does not expose the key when listing the integrations' do
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'sk-valida' })

    get api_v1_account_integrations_apps_url(account_id: account.id),
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:success)
    expect(response.body).not_to include('sk-valida')
  end

  it 'refuses a key the OpenAI account rejects and says why' do
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(false)

    post api_v1_account_integrations_hooks_url(account_id: account.id),
         params: { app_id: 'crm_kanban_ai', settings: { api_key: 'sk-recusada' } },
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['message']).to include('OpenAI')
    expect(account.hooks.where(app_id: 'crm_kanban_ai')).to be_empty
  end
end
