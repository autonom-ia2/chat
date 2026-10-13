require 'rails_helper'

# #1385: a tela de passagem lista "quem recebe" a partir da equipe das caixas do funil. Essa lista vem junto do
# ai_settings, para quem tem só a IA do CRM na função (sem poder abrir as configurações da caixa) ver e escolher a equipe.
RSpec.describe 'CRM AI settings team for the handoff screen', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:gestora) { create(:user, account: account, role: :agent) }
  let(:ana) { create_crm_agent(account: account, name: 'Ana do site').first }
  let(:leo) { create_crm_agent(account: account, name: 'Léo do WhatsApp').first }
  let(:fora) { create_crm_agent(account: account, name: 'Zeca de outra caixa').first }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings" }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run } }

  before do
    site = create_crm_inbox(account: account, name: 'Site', members: [ana, leo])
    whatsapp = create_crm_inbox(account: account, name: 'WhatsApp', members: [leo])
    create_crm_inbox(account: account, name: 'Outra caixa', members: [fora])
    [site, whatsapp].each do |inbox|
      Crm::PipelineInbox.create!(account: account, pipeline: pipeline, inbox: inbox, created_by: admin)
    end
    role = create(:custom_role, account: account, permissions: %w[crm_view crm_manage_ai])
    gestora.account_users.find_by!(account: account).update!(custom_role: role)
  end

  it 'quem tem só a IA do CRM recebe a equipe das caixas do funil, uma vez cada pessoa' do
    # Act
    get url, headers: gestora.create_new_auth_token, as: :json

    # Assert
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'team')).to eq(
      [{ 'id' => ana.id, 'name' => 'Ana do site' }, { 'id' => leo.id, 'name' => 'Léo do WhatsApp' }]
    )
    expect(response.parsed_body.dig('payload', 'inboxes').pluck('name')).to eq(%w[Site WhatsApp])
  end

  it 'não mostra quem saiu da conta, mesmo que tenha ficado registrado na caixa' do
    # Arrange — a linha da caixa sobrou; a da conta não existe mais
    AccountUser.where(account: account, user: leo).delete_all

    # Act
    get url, headers: gestora.create_new_auth_token, as: :json

    # Assert
    expect(response.parsed_body.dig('payload', 'team').pluck('name')).to eq(['Ana do site'])
  end

  it 'devolve a equipe também depois de salvar' do
    # Act
    patch url, params: { ai_settings: { handoff: { enabled: true } } }, headers: gestora.create_new_auth_token, as: :json

    # Assert
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'team').pluck('name')).to eq(['Ana do site', 'Léo do WhatsApp'])
  end
end
