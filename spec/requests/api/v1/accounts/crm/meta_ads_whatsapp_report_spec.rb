require 'rails_helper'

# Resumo e alerta de Anúncios da Meta no WhatsApp (#1100, F4b): só administrador, só a conta da sessão, erros de
# regra em 422 e teste com teto por hora. WAHA e envio em stub: nada sai de verdade.
RSpec.describe 'CRM meta_ads_connection whatsapp_report API', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/whatsapp_report" }
  let(:waha) { instance_double(Waha::Client) }
  let(:waha_inbox) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'vendas' }).inbox }
  let(:test_key) { "#{Api::V1::Accounts::Crm::MetaAdsWhatsappReportsController::TEST_KEY_PREFIX}:#{account.id}" }

  before do
    account.enable_features!('meta_ads_hub')
    allow(Waha::Config).to receive(:enabled?).and_return(true)
    allow(Waha::Client).to receive(:new).and_return(waha)
    allow(waha).to receive(:get_session).with('vendas').and_return({ 'status' => 'WORKING', 'me' => { 'id' => '5511999990000@c.us' } })
  end

  after { Redis::Alfred.delete(test_key) }

  describe 'GET' do
    it 'sem conexão devolve null' do
      get path, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('whatsapp_report' => nil)
    end

    it 'devolve a configuração desligada, as origens conectadas, os modelos e os horários' do
      create_meta_ads_insights_connection(account)
      waha_inbox

      get path, headers: auth_headers(admin), as: :json

      body = response.parsed_body['whatsapp_report']
      expect(body).to include('enabled' => false, 'alert_enabled' => false, 'inbox_id' => nil, 'phone' => nil, 'last_error' => nil)
      expect(body['origins']).to eq([{ 'inbox_id' => waha_inbox.id, 'name' => waha_inbox.name, 'phone_number' => '+5511999990000',
                                       'kind' => 'waha', 'templates' => nil }])
      expect(body['template_texts'].keys).to contain_exactly('summary', 'alert')
      expect(body['schedule']).to eq('summary_local_time' => '08:00', 'alert_local_time' => '16:30', 'time_zone' => 'America/Sao_Paulo')
    end

    it 'recusa agente com 403' do
      create_meta_ads_insights_connection(account)

      get path, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'forbidden')
    end
  end

  describe 'PATCH' do
    let!(:connection) { create_meta_ads_insights_connection(account) }

    it 'liga o resumo com a origem conectada e o número em E.164' do
      patch path, params: { whatsapp_report: { enabled: true, inbox_id: waha_inbox.id, phone: '11 98765-4321' } },
                  headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['whatsapp_report']).to include('enabled' => true, 'alert_enabled' => false, 'inbox_id' => waha_inbox.id,
                                                                 'phone' => '+5511987654321')
      expect(connection.reload.whatsapp_report_phone).to eq('+5511987654321')
    end

    it 'erros de regra em 422 e desligar sempre funciona' do
      other_account_inbox = create(:channel_api, account: create(:account),
                                                 additional_attributes: { 'provider' => 'waha', 'session' => 'vendas' }).inbox
      {
        { phone: 'abc' } => 'invalid_phone',
        { inbox_id: other_account_inbox.id } => 'inbox_not_connected',
        { enabled: true } => 'origin_required',
        { alert_enabled: true, inbox_id: waha_inbox.id } => 'phone_required'
      }.each do |body, code|
        patch path, params: { whatsapp_report: body }, headers: auth_headers(admin), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => code)
      end

      patch path, params: { whatsapp_report: { enabled: false, alert_enabled: false } }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'sem Anúncios da Meta ligado na conta, não grava nem testa' do
      account.disable_features!('meta_ads_hub')

      patch path, params: { whatsapp_report: { enabled: false } }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'feature_disabled')

      post "#{path}/test", headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'agente não grava' do
      patch path, params: { whatsapp_report: { enabled: false } }, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST test' do
    let(:sender) { instance_double(Crm::MetaAds::WhatsappReport::Sender) }

    before { allow(Crm::MetaAds::WhatsappReport::Sender).to receive(:new).and_return(sender) }

    it 'sem conexão é not_connected; sem origem salva é origin_required' do
      post "#{path}/test", headers: auth_headers(admin), as: :json
      expect(response.parsed_body).to eq('error' => 'not_connected')

      create_meta_ads_insights_connection(account)
      post "#{path}/test", headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'origin_required')
    end

    it 'manda o resumo de ontem como teste, até 3 por hora' do
      travel_to(Time.zone.parse('2026-10-07T10:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        connection.update!(whatsapp_report: { 'inbox_id' => waha_inbox.id }, whatsapp_report_phone: '+5511987654321')
        allow(sender).to receive(:send_summary).and_return(true)

        3.times do
          post "#{path}/test", headers: auth_headers(admin), as: :json
          expect(response).to have_http_status(:ok)
        end
        expect(response.parsed_body).to eq('sent' => true, 'sent_at' => '2026-10-07T13:00:00Z')
        expect(sender).to have_received(:send_summary).thrice.with(hash_including(date: Date.new(2026, 10, 6)), test: true)

        post "#{path}/test", headers: auth_headers(admin), as: :json
        expect(response).to have_http_status(:too_many_requests)
        expect(response.parsed_body).to eq('error' => 'rate_limited')
      end
    end

    it 'falha de envio vira 422 com o código' do
      connection = create_meta_ads_insights_connection(account)
      connection.update!(whatsapp_report: { 'inbox_id' => waha_inbox.id }, whatsapp_report_phone: '+5511987654321')
      allow(sender).to receive(:send_summary).and_raise(Crm::MetaAds::WhatsappReport::Settings::Error.new('send_uncertain'))

      post "#{path}/test", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'send_uncertain')
    end

    it 'agente não testa' do
      post "#{path}/test", headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
