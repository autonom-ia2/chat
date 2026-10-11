require 'rails_helper'

# Modelos de aviso do WhatsApp oficial no painel (#1272): a sugestão da IA e o estado dos pedidos (quem configura
# páginas) e a criação na Meta (só administrador, só no clique, num job), com a IA e a Meta simuladas.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages notice templates', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:page) { create_booking_profile(account: account, host: admin) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:cloud) { channel.inbox }
  let(:member) { "/api/v1/accounts/#{account.id}/crm/booking_pages/#{page.id}" }
  let(:templates_url) { "https://graph.facebook.com/v14.0/#{channel.provider_config['business_account_id']}/message_templates" }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:json) { { 'Content-Type' => 'application/json' } }
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

  def stub_meta(status: 200, body: { id: 'tpl1', status: 'PENDING' })
    stub_request(:get, templates_url).with(query: hash_including({})).to_return(status: 200, body: { data: [] }.to_json, headers: json)
    stub_request(:post, templates_url).to_return(status: status, body: body.to_json, headers: json)
  end

  describe 'POST notice_template_suggestions' do
    let(:path) { "#{member}/notice_template_suggestions" }

    it 'sugere o modelo de cada aviso e diz que o administrador pode criar os que faltam, sem chamar a Meta' do
      call(admin, :post, path, inbox_id: cloud.id, kinds: %w[booked day_before])

      expect(response).to have_http_status(:ok)
      expect(payload).to eq(
        'suggestions' => { 'booked' => { 'name' => 'lembrete_horario', 'language' => 'pt_BR', 'reason' => 'Fala do horário.' },
                           'day_before' => nil },
        'ai_failed' => false, 'can_create' => true, 'requests' => {}
      )
      expect(a_request(:any, /graph.facebook.com/)).not_to have_been_made
    end

    it 'quem gerencia páginas sem ser administrador recebe a sugestão, mas não o botão de criar' do
      call(role_user('agendamento_manage'), :post, path, inbox_id: cloud.id, kinds: %w[booked])

      expect(response).to have_http_status(:ok)
      expect(payload['suggestions']['booked']).to include('name' => 'lembrete_horario')
      expect(payload['can_create']).to be(false)
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

  describe 'POST notice_templates/create e GET notice_templates' do
    let(:path) { "#{member}/notice_templates/create" }

    it 'o administrador enfileira, responde na hora com "enviando" e o job deixa "em aprovação"' do
      stub_meta

      call(admin, :post, path, inbox_id: cloud.id, kinds: %w[booked hour_before])

      expect(response).to have_http_status(:accepted)
      expect(payload['queued']).to be(true)
      expect(payload['requests'].transform_values { |entry| entry['state'] }).to eq('booked' => 'sending', 'hour_before' => 'sending')
      expect(a_request(:post, templates_url)).not_to have_been_made

      perform_enqueued_jobs
      call(admin, :get, "#{member}/notice_templates", inbox_id: cloud.id)

      expect(payload['requests'].transform_values { |entry| entry['state'] }).to eq('booked' => 'pending', 'hour_before' => 'pending')
      expect(a_request(:post, templates_url)).to have_been_made.twice
    end

    it 'clique duplo enfileira uma vez só' do
      stub_meta

      expect do
        2.times { call(admin, :post, path, inbox_id: cloud.id, kinds: %w[booked]) }
      end.to have_enqueued_job(Crm::BookingV2::NoticeTemplatesJob).exactly(:once)
      expect(payload['queued']).to be(false)
    end

    it 'quem gerencia páginas sem ser administrador não cria modelo na Meta, mas acompanha o estado' do
      manager = role_user('agendamento_manage')

      expect { call(manager, :post, path, inbox_id: cloud.id, kinds: %w[booked]) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unauthorized)

      call(manager, :get, "#{member}/notice_templates", inbox_id: cloud.id)
      expect(response).to have_http_status(:ok)
    end

    it 'sem permissão na Meta: o estado mostra o texto para reconectar a caixa' do
      stub_meta(status: 403, body: { error: { message: 'Permission denied', type: 'OAuthException', code: 200 } })

      perform_enqueued_jobs { call(admin, :post, path, inbox_id: cloud.id, kinds: %w[booked]) }
      call(admin, :get, "#{member}/notice_templates", inbox_id: cloud.id)

      expect(payload['requests']['booked']['state']).to eq('failed')
      expect(payload['requests']['booked']['reason']).to start_with('A conexão deste WhatsApp não tem permissão para criar modelos.')
      expect(response.body).not_to include(channel.template_access_token)
    end

    it 'caixa de outra conta não serve, nem para o administrador' do
      foreign = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox

      expect { call(admin, :post, path, inbox_id: foreign.id, kinds: %w[booked]) }.not_to have_enqueued_job
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'caixa 360dialog não cria' do
      dialog = create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false).inbox

      call(admin, :post, path, inbox_id: dialog.id, kinds: %w[booked])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.booking_v2.notice_templates_unsupported')
    end
  end
end
