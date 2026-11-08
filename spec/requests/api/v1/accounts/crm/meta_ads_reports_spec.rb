require 'rails_helper'

# Relatório baixado de Anúncios (#1960): PDF e planilha com os números da tela. Quem vê o painel baixa; sem painel, 404;
# formato desconhecido, 422.
RSpec.describe 'CRM meta_ads_connection report API', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/report" }
  let(:ad_id) { '120254710362980416' }

  def from_ad(title: 'Marina Souza')
    contact = create(:contact, account: account, name: title)
    conversation = create(:conversation, account: account, contact: contact)
    click = { 'source' => 'meta_ctwa', 'source_id' => ad_id, 'source_type' => 'ad', 'headline' => 'Fale com a gente',
              'touched_at' => 1.day.ago.utc.iso8601 }
    conversation.update_columns(additional_attributes: { 'campaign' => click, 'campaign_touches' => [click] }) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def sem_login!
    account.enable_features!('anuncios_sem_login')
    create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
  end

  before { account.enable_features!('meta_ads_hub') }

  it 'baixa o PDF do painel do WhatsApp, com o nome do arquivo e os números do período' do
    sem_login!
    from_ad

    get path, params: { formato: 'pdf', days: 30 }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    expect(response.headers['Content-Disposition']).to include('attachment').and include('.pdf')
    texto = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    expect(texto).to include('Fale com a gente', 'Marina Souza')
  end

  it 'baixa a planilha com as quatro abas e a conversa na aba de conversas' do
    sem_login!
    from_ad

    get path, params: { formato: 'planilha', days: 7 }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    planilha = Roo::Excelx.new(StringIO.new(response.body))
    expect(planilha.sheets.size).to eq(4)
    conversas = planilha.sheet(2)
    expect((1..conversas.last_row).map { |linha| conversas.row(linha) }.flatten).to include('Marina Souza', 'Fale com a gente')
  end

  it 'recusa formato desconhecido com 422' do
    sem_login!

    get path, params: { formato: 'csv' }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'sem painel (sem conexão e sem Anúncios sem login) devolve 404' do
    get path, params: { formato: 'pdf' }, headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
  end

  it 'recusa quem não vê o painel com 403' do
    sem_login!

    get path, params: { formato: 'pdf' }, headers: auth_headers(agent)

    expect(response).to have_http_status(:forbidden)
  end
end
