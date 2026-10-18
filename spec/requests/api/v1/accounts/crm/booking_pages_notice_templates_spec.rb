require 'rails_helper'

# Modelos de aviso do WhatsApp oficial no painel (#1272): a sugestão da IA (quem configura páginas), com a IA simulada.
# O "Criar os modelos na Meta" (v1) saiu em #1612: a rota não existe mais e a sugestão não oferece criar.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages notice templates', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:page) { create_booking_profile(account: account, host: admin) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:cloud) { channel.inbox }
  let(:member) { "/api/v1/accounts/#{account.id}/crm/booking_pages/#{page.id}" }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:good) do
    { 'name' => 'lembrete_horario', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie em {{3}} quando quiser.' }] }
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'CRM_AI_ENABLED' => 'true') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    channel.update_columns(message_templates: [good]) # rubocop:disable Rails/SkipsModelValidations
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:create).and_return(text: { choices: [{ kind: 'booked', index: 0, reason: 'Fala do horário.' }] }.to_json)
  end

  def role_user(*permissions, member_of: cloud)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    create(:inbox_member, user: user, inbox: member_of) if member_of
    user
  end

  def call(user, verb, path, params)
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: verb == :get ? nil : :json)
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'POST notice_template_suggestions' do
    let(:path) { "#{member}/notice_template_suggestions" }

    it 'sugere o modelo de cada aviso, sem chamar a Meta e sem oferecer criar modelo' do
      call(admin, :post, path, inbox_id: cloud.id, kinds: %w[booked day_before])

      expect(response).to have_http_status(:ok)
      expect(payload).to eq(
        'suggestions' => { 'booked' => { 'name' => 'lembrete_horario', 'language' => 'pt_BR', 'reason' => 'Fala do horário.' },
                           'day_before' => nil },
        'ai_failed' => false
      )
    end

    it 'quem gerencia páginas sem ser administrador recebe a sugestão' do
      call(role_user('agendamento_manage'), :post, path, inbox_id: cloud.id, kinds: %w[booked])

      expect(response).to have_http_status(:ok)
      expect(payload['suggestions']['booked']).to include('name' => 'lembrete_horario')
    end

    it 'caixa fora do escopo de quem gerencia (não é membro) não serve' do
      call(role_user('agendamento_manage', member_of: nil), :post, path, inbox_id: cloud.id)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'quem só vê páginas não pede sugestão' do
      call(role_user('agendamento_view'), :post, path, inbox_id: cloud.id)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'falha da IA: 200 com ai_failed' do
      allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'boom')

      call(admin, :post, path, inbox_id: cloud.id, kinds: %w[booked])

      expect(response).to have_http_status(:ok)
      expect(payload).to include('suggestions' => {}, 'ai_failed' => true)
    end

    it 'recusa caixa que não é WhatsApp oficial' do
      waha = create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }).inbox

      call(admin, :post, path, inbox_id: waha.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.booking_v2.notice_inbox_invalid')
    end

    it 'com a flag desligada, 404' do
      account.disable_features('crm_booking_v2')
      account.save!

      call(admin, :post, path, inbox_id: cloud.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'criar os modelos na Meta (v1, retirado em #1612)' do
    it 'nem o administrador cria: a rota de criar e a do estado dos pedidos não existem mais' do
      expect { call(admin, :post, "#{member}/notice_templates/create", inbox_id: cloud.id, kinds: %w[booked]) }.not_to have_enqueued_job
      expect(response).to have_http_status(:not_found)

      call(admin, :get, "#{member}/notice_templates", inbox_id: cloud.id)
      expect(response).to have_http_status(:not_found)
    end
  end
end
