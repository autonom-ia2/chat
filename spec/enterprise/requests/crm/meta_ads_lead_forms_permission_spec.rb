require 'rails_helper'

# Formulários do anúncio da Meta (#2195) com funções personalizadas (parecer da sessão Funções, 27/10):
# - meta_ads_view vê a tela, mas não liga, para, escolhe destino nem traz antigos (403 antes de chamar a Meta);
# - abrir a tela só para ver não grava Página; as Páginas lidas só ficam guardadas quando quem abre tem meta_ads_manage (#2357);
# - a lista de quem chegou (nome, telefone, e-mail) pede também contact_view;
# - trazer em lote cria cards: pede também crm_manage_cards, mesmo com meta_ads_manage.
RSpec.describe 'Formulários da Meta com funções personalizadas', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_lead_forms" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:page_token) { 'page-token-de-teste' }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:destination) { { pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id } }

  before do
    enable_test_encryption!
    account.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(account)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def stub_pages
    pages = { data: [{ id: '104882', name: 'Studio Aurora', access_token: page_token }] }
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: pages.to_json)
    stub_request(:get, meta_graph_url('104882/leadgen_forms')).with(query: hash_including({}))
                                                              .to_return(status: 200, headers: json, body: { data: [] }.to_json)
  end

  describe 'só meta_ads_view' do
    let(:marketing) { pessoa_com(%w[meta_ads_view]) }

    it 'vê a tela, sem a lista de quem chegou' do
      stub_pages

      get path, headers: auth_headers(marketing), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['recent_leads']).to be_nil
    end

    it 'abrir a tela não grava as Páginas lidas' do
      stub_pages

      expect { get path, headers: auth_headers(marketing), as: :json }.not_to change(Crm::MetaAdsPage, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['pages']).to contain_exactly(include('id' => '104882', 'name' => 'Studio Aurora'))
    end

    it 'abrir a tela não renomeia a Página já guardada' do
      Crm::MetaAdsPage.create!(account: account, page_id: '104882', name: 'Nome antigo')
      stub_pages

      get path, headers: auth_headers(marketing), as: :json

      expect(Crm::MetaAdsPage.find_by(account: account, page_id: '104882').name).to eq('Nome antigo')
    end

    it 'com contact_view vê também a lista de quem chegou' do
      stub_pages

      get path, headers: auth_headers(pessoa_com(%w[meta_ads_view contact_view])), as: :json

      expect(response.parsed_body['recent_leads']).to eq([])
    end

    it 'não liga, não para, não escolhe nem tira destino e não traz antigos: 403 sem chamar a Meta' do
      headers = auth_headers(marketing)

      post "#{path}/pages/104882/receive", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{path}/pages/104882/receive", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      put "#{path}/forms/9001/destination", params: destination, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      delete "#{path}/forms/9001/destination", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{path}/forms/9003/bring_past", params: destination, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)

      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'meta_ads_manage sem criar card no CRM' do
    let(:gestor) { pessoa_com(%w[meta_ads_view meta_ads_manage crm_view]) }

    it 'abrir a tela guarda as Páginas lidas' do
      stub_pages

      get path, headers: auth_headers(gestor), as: :json

      expect(response).to have_http_status(:ok)
      expect(Crm::MetaAdsPage.where(account: account).pluck(:page_id, :name)).to eq([['104882', 'Studio Aurora']])
    end

    # O webhook acha a conta pela linha da Página: ligar sem ter aberto a tela antes tem de criá-la.
    it 'ligar a Página sem abrir a tela antes deixa a Página achável pelo webhook' do
      stub_pages
      subscription = instance_double(Crm::MetaAds::PageSubscription, add!: true)
      allow(Crm::MetaAds::PageSubscription).to receive(:new).and_return(subscription)

      post "#{path}/pages/104882/receive", headers: auth_headers(gestor), as: :json

      expect(response).to have_http_status(:ok)
      expect(Crm::MetaAdsPage.account_ids_for('104882')).to eq([account.id])
      expect(Crm::MetaAdsPage.leadgen_receiving.pluck(:page_id)).to eq(['104882'])
    end

    it 'não traz antigos de formulário arquivado: 403 sem chamar a Meta' do
      post "#{path}/forms/9003/bring_past", params: destination, headers: auth_headers(gestor), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'não escolhe destino trazendo quem já preencheu: 403 sem chamar a Meta' do
      put "#{path}/forms/9001/destination", params: destination.merge(import_past: true), headers: auth_headers(gestor), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end
end
