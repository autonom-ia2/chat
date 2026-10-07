require 'rails_helper'

# Gestos sobre as ações do consultor (#1110, F5): abrir não aceita (D5.9), aceitar e dispensar só de `open`, e o
# pedido que vem pelo cabeçalho api_access_token (o Guia) fica marcado como `api` (D5.11).
RSpec.describe 'CRM meta_ads_connection advisor actions (F5)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/advisor_actions" }
  let(:advisor_action) { create_advisor_action(account) }

  def create_advisor_action(owner, status: :open, kind: 'stalled_quotes')
    Crm::MetaAdvisorAction.create!(account: owner, local_date: Date.new(2026, 10, 7), kind: kind, subject_key: 'account',
                                   position: 1, status: status, shown_at: Time.current)
  end

  # O painel autentica pela sessão (devise_token_auth), não pelo token de API.
  def panel_headers(user)
    user.create_new_auth_token
  end

  it 'abrir grava quem, quando e de onde, sem mudar o status' do
    post "#{path}/#{advisor_action.id}/open", headers: panel_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['advisor_action']).to include('id' => advisor_action.id, 'status' => 'open', 'resolved_at' => nil)
    expect(response.parsed_body.dig('advisor_action', 'opened_at')).to be_present
    expect(advisor_action.reload).to have_attributes(opened_by_id: admin.id, opened_via: 'panel', status: 'open')
  end

  it 'abrir de novo responde 200 e não muda o primeiro registro' do
    post "#{path}/#{advisor_action.id}/open", headers: panel_headers(admin), as: :json
    first_opened_at = advisor_action.reload.opened_at

    travel(1.hour) { post "#{path}/#{advisor_action.id}/open", headers: auth_headers(admin), as: :json }

    expect(response).to have_http_status(:ok)
    expect(advisor_action.reload).to have_attributes(opened_at: first_opened_at, opened_via: 'panel')
  end

  it 'aceitar resolve pelo painel' do
    post "#{path}/#{advisor_action.id}/accept", headers: panel_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['advisor_action']).to include('status' => 'accepted')
    expect(response.parsed_body.dig('advisor_action', 'resolved_at')).to be_present
    expect(advisor_action.reload).to have_attributes(resolved_by_id: admin.id, resolved_via: 'panel')
  end

  it 'aceitar ou dispensar o que já foi aceito dá 422 not_open' do
    advisor_action.accept!(admin, via: 'panel')

    post "#{path}/#{advisor_action.id}/accept", headers: panel_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'not_open')

    post "#{path}/#{advisor_action.id}/dismiss", headers: panel_headers(admin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(advisor_action.reload.status).to eq('accepted')
  end

  it 'dispensar resolve a ação aberta; ação vencida não pode ser dispensada' do
    post "#{path}/#{advisor_action.id}/dismiss", headers: panel_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(advisor_action.reload).to have_attributes(status: 'dismissed', resolved_via: 'panel')

    expired = create_advisor_action(account, status: :expired, kind: 'fix_tracking')
    post "#{path}/#{expired.id}/dismiss", headers: panel_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'not_open')
  end

  it 'pelo cabeçalho api_access_token (como o Guia chama) o gesto fica marcado como api' do
    post "#{path}/#{advisor_action.id}/open", headers: auth_headers(admin), as: :json
    post "#{path}/#{advisor_action.id}/accept", headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(advisor_action.reload).to have_attributes(opened_via: 'api', resolved_via: 'api', status: 'accepted')
  end

  it 'ação de outra conta, ou que não existe, dá 404 sem mexer nela' do
    other = create_advisor_action(create(:account))

    post "#{path}/#{other.id}/accept", headers: panel_headers(admin), as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'not_found')
    expect(other.reload.status).to eq('open')

    post "#{path}/0/open", headers: panel_headers(admin), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'agente recebe 403 e a ação não muda' do
    %w[open accept dismiss].each do |gesture|
      post "#{path}/#{advisor_action.id}/#{gesture}", headers: panel_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'forbidden')
    end
    expect(advisor_action.reload).to have_attributes(status: 'open', opened_at: nil)
  end
end
