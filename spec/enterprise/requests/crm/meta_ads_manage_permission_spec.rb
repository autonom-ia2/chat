require 'rails_helper'

# Funções personalizadas, lote 12 (#2070): `meta_ads_manage` conecta, configura e desconecta Anúncios da Meta e age
# sobre o consultor, como o administrador. Chave protegida (#1782, D7 do lote 11): só o administrador entrega.
# `meta_ads_view` segue só vendo; agente comum, nada. Fica em spec/enterprise: a metade de função personalizada do
# permission_granted? é EE.
RSpec.describe 'Anúncios da Meta com meta_ads_manage (#2070)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:plain_agent) { create_crm_agent(account: account).first }
  let(:manager) { pessoa_com(%w[meta_ads_manage]) }
  let(:viewer) { pessoa_com(%w[meta_ads_view]) }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:token) { 'EAAGnovotoken9876543210zyxwvutSEGREDO' }

  before { enable_test_encryption! }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def stub_token_check
    stub_request(:get, meta_graph_url('me/permissions'))
      .with(headers: { 'Authorization' => "Bearer #{token}" })
      .to_return(status: 200, body: { data: [{ permission: 'ads_read', status: 'granted' }] }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, meta_graph_url('me/adaccounts'))
      .with(query: { limit: '1', fields: 'id' }, headers: { 'Authorization' => "Bearer #{token}" })
      .to_return(status: 200, body: { data: [{ id: 'act_123' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def expect_forbidden_for_viewer_and_agent
    [viewer, plain_agent].each do |user|
      yield auth_headers(user)
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'vê a conexão: manage implica view' do
    create_meta_ads_connection(account)

    get path, headers: auth_headers(manager), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('configured' => true)
  end

  it 'cola o token; quem só vê e o agente comum, não' do
    stub_token_check

    expect_forbidden_for_viewer_and_agent { |headers| put path, params: { access_token: token }, headers: headers, as: :json }
    expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty

    put path, params: { access_token: token }, headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsConnection.find_by(account_id: account.id)).to have_attributes(mode: 'token', status: 'active')
  end

  it 'desconecta; quem só vê e o agente comum, não' do
    create_meta_ads_connection(account)

    expect_forbidden_for_viewer_and_agent { |headers| delete path, headers: headers, as: :json }
    expect(Crm::MetaAdsConnection.where(account_id: account.id)).to exist

    delete path, headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
  end

  it 'troca para onde os anúncios levam' do
    connection = create_meta_ads_insights_connection(account)
    params = { destinations: { whatsapp: true, site: false } }

    expect_forbidden_for_viewer_and_agent { |headers| patch "#{path}/destinations", params: params, headers: headers, as: :json }

    patch "#{path}/destinations", params: params, headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(connection.reload.destinations).to eq('whatsapp' => true, 'site' => false)
  end

  describe 'funil (avisar a Meta das vendas)' do
    let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
    let!(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Viagem').first }
    let!(:proposal) { create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta') }

    before do
      create_meta_ads_insights_connection(account)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: whatsapp_inbox)
    end

    it 'lista os funis e liga o aviso; quem só vê e o agente comum, não' do
      params = { pipeline_id: pipeline.id, stages: [{ id: proposal.id, funnel_stage_type: 'opportunity' }] }

      expect_forbidden_for_viewer_and_agent { |headers| patch "#{path}/funnel", params: params, headers: headers, as: :json }
      expect(pipeline.reload.metadata['meta_sync']).to be_nil

      get "#{path}/funnels", headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['funnels'].pluck('name')).to eq(['Viagem'])

      patch "#{path}/funnel", params: params, headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:ok)
      expect(pipeline.reload.metadata.dig('meta_sync', 'enabled')).to be(true)
    end
  end

  it 'lê o resumo no WhatsApp; quem só vê e o agente comum, não' do
    create_meta_ads_insights_connection(account)

    expect_forbidden_for_viewer_and_agent { |headers| get "#{path}/whatsapp_report", headers: headers, as: :json }

    get "#{path}/whatsapp_report", headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['whatsapp_report']).to be_present
  end

  it 'marca a ação do consultor como feita; quem só vê e o agente comum, não' do
    advisor_action = Crm::MetaAdvisorAction.create!(account: account, local_date: Date.new(2026, 10, 7), kind: 'stalled_quotes',
                                                    subject_key: 'account', position: 1, status: :open, shown_at: Time.current)

    expect_forbidden_for_viewer_and_agent do |headers|
      post "#{path}/advisor_actions/#{advisor_action.id}/accept", headers: headers, as: :json
    end
    expect(advisor_action.reload.status).to eq('open')

    post "#{path}/advisor_actions/#{advisor_action.id}/accept", headers: auth_headers(manager), as: :json
    expect(response).to have_http_status(:ok)
    expect(advisor_action.reload).to have_attributes(status: 'accepted', resolved_by_id: manager.id)
  end

  it 'o administrador segue fazendo tudo' do
    create_meta_ads_insights_connection(account)

    get "#{path}/whatsapp_report", headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)

    delete path, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
  end

  # Sem login (#1960): quem configura os anúncios vê todos os WhatsApp oficiais prontos, como o administrador.
  it 'na tela vazia, manage vê todos os WhatsApp oficiais; quem só vê, os da própria caixa' do
    account.enable_features!('anuncios_sem_login')
    dela = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    alheia = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
    dela.add_members([viewer.id, manager.id])

    get path, headers: auth_headers(manager), as: :json
    expect(response.parsed_body.dig('whatsapp_result', 'official_inboxes').pluck('id')).to contain_exactly(dela.id, alheia.id)

    get path, headers: auth_headers(viewer), as: :json
    expect(response.parsed_body.dig('whatsapp_result', 'official_inboxes').pluck('id')).to eq([dela.id])
  end

  describe 'delegação' do
    before { account.enable_features!('custom_roles') }

    def create_role(as:, name:, permissions:)
      post "/api/v1/accounts/#{account.id}/custom_roles",
           params: { custom_role: { name: name, permissions: permissions } }, headers: as.create_new_auth_token, as: :json
    end

    it 'quem monta funções entrega meta_ads_view, mas não meta_ads_manage, mesmo tendo a chave' do
      builder = pessoa_com(%w[custom_role_manage meta_ads_manage])

      create_role(as: builder, name: 'Só olha', permissions: %w[meta_ads_view])
      expect(response).to have_http_status(:ok)

      create_role(as: builder, name: 'Anúncios', permissions: %w[meta_ads_manage])
      expect(response).to have_http_status(:unauthorized)
      expect(account.custom_roles.where(name: 'Anúncios')).to be_empty
    end

    it 'quem tem o ajuste Pode entregar acima do próprio (grant_above_own) entrega meta_ads_manage' do
      builder = pessoa_com(%w[custom_role_manage grant_above_own])

      create_role(as: builder, name: 'Anúncios', permissions: %w[meta_ads_manage])

      expect(response).to have_http_status(:ok)
      expect(account.custom_roles.find_by(name: 'Anúncios').permissions).to eq(%w[meta_ads_manage])
    end

    it 'o administrador entrega' do
      create_role(as: admin, name: 'Anúncios', permissions: %w[meta_ads_manage])

      expect(response).to have_http_status(:ok)
      expect(account.custom_roles.find_by(name: 'Anúncios').permissions).to eq(%w[meta_ads_manage])
    end
  end
end
