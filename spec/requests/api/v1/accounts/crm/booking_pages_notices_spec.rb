require 'rails_helper'

# Avisos da página no painel (#1192): caixa de avisos (só as que a pessoa enxerga e que mandam WhatsApp), jogo de
# avisos (J5-A8), modelos, prazo de mudança e "Testar no meu WhatsApp" (J3-A11) com a matriz de permissão.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages notices', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:page) { world.profile }
  let(:member) { "/api/v1/accounts/#{account.id}/crm/booking_pages/#{page.id}" }
  let(:cloud) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:dialog) { create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false).inbox }
  let(:waha) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }).inbox }
  let(:plain_api) { create(:channel_api, account: account).inbox }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      example.run
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'GET show' do
    it 'devolve os campos de avisos e só as caixas que mandam WhatsApp' do
      [cloud, dialog, waha, plain_api]

      call(admin, :get, member)

      expect(payload).to include('notice_inbox_id' => nil, 'notice_preset' => 'standard', 'notice_templates' => {}, 'cancel_until_minutes' => 120)
      expect(payload['notice_inbox_options']).to contain_exactly(
        { 'id' => cloud.id, 'name' => cloud.name, 'channel_type' => 'Channel::Whatsapp', 'provider' => 'whatsapp_cloud', 'needs_templates' => true },
        { 'id' => dialog.id, 'name' => dialog.name, 'channel_type' => 'Channel::Whatsapp', 'provider' => '360dialog', 'needs_templates' => true },
        { 'id' => waha.id, 'name' => waha.name, 'channel_type' => 'Channel::Api', 'provider' => 'waha', 'needs_templates' => false }
      )
    end

    it 'quem gerencia sem ser admin só vê as caixas de que é membro' do
      manager = role_user('agendamento_manage')
      create(:inbox_member, user: manager, inbox: cloud)
      dialog

      call(manager, :get, member)

      expect(payload['notice_inbox_options'].pluck('id')).to eq([cloud.id])
    end
  end

  describe 'PATCH update' do
    it 'grava caixa, jogo, modelos e prazo' do
      call(admin, :patch, member, booking_page: {
             notice_inbox_id: cloud.id, notice_preset: 'light', cancel_until_minutes: 60,
             notice_templates: { booked: { name: 'aviso_marcado', language: 'pt_BR' }, hour_before: { id: '7' } }
           })

      expect(response).to have_http_status(:ok)
      expect(page.reload).to have_attributes(notice_inbox_id: cloud.id, notice_preset: 'light', cancel_until_minutes: 60)
      expect(page.notice_templates).to eq('booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' }, 'hour_before' => { 'id' => 7 })
      expect(payload).to include('notice_inbox_id' => cloud.id, 'notice_preset' => 'light')
    end

    it 'recusa caixa que não manda WhatsApp, de outra conta ou fora do escopo da pessoa' do
      foreign = create(:channel_whatsapp, validate_provider_config: false, sync_templates: false).inbox

      [plain_api, foreign].each do |inbox|
        call(admin, :patch, member, booking_page: { notice_inbox_id: inbox.id })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('crm.booking_v2.notice_inbox_invalid')
      end
      expect(page.reload.notice_inbox_id).to be_nil
    end

    it 'recusa jogo, prazo e modelo inválidos' do
      [{ notice_preset: 'turbo' }, { cancel_until_minutes: -1 }, { notice_templates: { booked: { name: 'x' } } }].each do |attrs|
        call(admin, :patch, member, booking_page: attrs)
        expect(response).to have_http_status(:unprocessable_entity), attrs.inspect
      end
      expect(page.reload).to have_attributes(notice_preset: 'standard', cancel_until_minutes: 120, notice_templates: {})
    end

    it 'recusa modelo da Meta já sincronizado sem {{3}} (sem link de gestão nem de parar) e aceita o que tem (RA-18)' do
      cloud.channel.update!(message_templates: [
                              { 'name' => 'sem_link', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, até {{2}}.' }] },
                              { 'name' => 'com_link', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, até {{2}}. Veja: {{3}}' }] }
                            ])

      call(admin, :patch, member, booking_page: { notice_inbox_id: cloud.id, notice_templates: { booked: { name: 'sem_link', language: 'pt_BR' } } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors']['notice_templates']).to eq(['must include {{3}} (manage link): booked'])
      expect(page.reload).to have_attributes(notice_inbox_id: nil, notice_templates: {})

      call(admin, :patch, member, booking_page: { notice_inbox_id: cloud.id, notice_templates: { booked: { name: 'com_link', language: 'pt_BR' } } })

      expect(response).to have_http_status(:ok)
      expect(page.reload.notice_templates).to eq('booked' => { 'name' => 'com_link', 'language' => 'pt_BR' })
    end

    it 'quem não enxerga a caixa de avisos já gravada salva os outros passos reenviando a mesma caixa, mas não troca a caixa' do
      page.update!(notice_inbox: cloud)
      manager = role_user('agendamento_manage')

      call(manager, :patch, member, booking_page: { notice_inbox_id: cloud.id, notice_preset: 'light' })

      expect(response).to have_http_status(:ok)
      expect(page.reload).to have_attributes(notice_inbox_id: cloud.id, notice_preset: 'light')

      call(manager, :patch, member, booking_page: { notice_inbox_id: dialog.id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.booking_v2.notice_inbox_invalid')
      expect(page.reload.notice_inbox_id).to eq(cloud.id)
    end

    it 'tira a caixa de avisos com nulo' do
      page.update!(notice_inbox: cloud)

      call(admin, :patch, member, booking_page: { notice_inbox_id: nil })

      expect(page.reload.notice_inbox_id).to be_nil
    end
  end

  describe 'POST test_invite (J3-A11)' do
    let(:path) { "#{member}/test_invite" }

    before { page.update!(notice_inbox: waha) }

    def open_window_for(phone)
      contact = account.contacts.create!(name: 'Admin Ana', phone_number: phone)
      conversation = create(:conversation, account: account, inbox: waha, contact: contact)
      create(:message, account: account, inbox: waha, conversation: conversation, message_type: :incoming, created_at: 1.hour.ago)
      conversation
    end

    it 'manda pela caixa de avisos um link igual ao do cliente, num convite de teste fora das listas' do
      conversation = open_window_for('+5511955554444')

      call(admin, :post, path, phone: '(11) 95555-4444')

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('sent' => true)
      invite = Crm::BookingInvite.sole
      expect(invite).to have_attributes(booking_profile_id: page.id, contact_id: conversation.contact_id, created_by_id: admin.id,
                                        metadata: { 'test' => true }, sent_at: be_present)
      message = conversation.messages.outgoing.sole
      expect(message.content).to include("https://app.example.com/b/#{invite.code}")
      expect(message.content).to start_with('Este é um teste da sua página de agendamento.')
      expect(Crm::BookingInvite.real).to be_empty

      get "/public/api/v2/invites/#{invite.code}"
      expect(response).to have_http_status(:ok)
    end

    it 'recusa com o motivo do canal quando não pode mandar, sem criar convite nem contato' do
      expect { call(admin, :post, path, phone: '+5511955554444') }.not_to change(Contact, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'cannot_send', 'reason' => 'waha_outside_window')
      expect(Crm::BookingInvite.count).to eq(0)
    end

    it 'recusa telefone inválido, página sem caixa de avisos e página despublicada' do
      call(admin, :post, path, phone: '123')
      expect(response.parsed_body).to eq('error' => 'invalid_phone')

      page.update!(enabled: false)
      call(admin, :post, path, phone: '+5511955554444')
      expect(response.parsed_body).to eq('error' => 'page_not_published')

      page.update!(enabled: true, notice_inbox: nil)
      call(admin, :post, path, phone: '+5511955554444')
      expect(response.parsed_body).to eq('error' => 'notice_inbox_missing')
    end

    it 'número que recusou mensagens ou parou os avisos não recebe o teste (RA-18)' do
      conversation = open_window_for('+5511955554444')
      contact = conversation.contact

      Crm::BookingNoticeStop.create!(account: account, contact: contact)
      call(admin, :post, path, phone: '+5511955554444')
      expect(response.parsed_body).to eq('error' => 'cannot_send', 'reason' => 'stopped')

      Crm::BookingNoticeStop.delete_all
      contact.update!(opted_out_at: Time.current, opt_out_source: 'manual')
      call(admin, :post, path, phone: '+5511955554444')
      expect(response.parsed_body).to eq('error' => 'cannot_send', 'reason' => 'stopped')

      expect(Crm::BookingInvite.count).to eq(0)
      expect(conversation.messages.outgoing).to be_empty
    end

    it 'quem gerencia precisa enxergar a caixa de avisos: sem ser membro, recusa sem gravar nada' do
      open_window_for('+5511955554444')
      outsider = role_user('agendamento_manage', 'conversation_manage')

      expect { call(outsider, :post, path, phone: '+5511955554444') }.not_to change(Contact, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'notice_inbox_forbidden')
      expect(Crm::BookingInvite.count).to eq(0)
      expect(Message.outgoing.count).to eq(0)
    end

    it 'conversa que já existe: só manda quem pode responder nela (mesmo critério do envio pelo painel)' do
      conversation = open_window_for('+5511955554444')
      participating = role_user('agendamento_manage', 'conversation_participating_manage')
      create(:inbox_member, user: participating, inbox: waha)

      call(participating, :post, path, phone: '+5511955554444')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'notice_inbox_forbidden', 'reason' => 'conversation_forbidden')
      expect(conversation.messages.outgoing).to be_empty
      expect(Crm::BookingInvite.count).to eq(0)

      conversation.update!(assignee: participating)
      call(participating, :post, path, phone: '+5511955554444')

      expect(response).to have_http_status(:ok)
      expect(conversation.messages.outgoing.count).to eq(1)
    end

    it 'só quem gerencia a página, enxerga a caixa e pode responder na conversa pode testar' do
      open_window_for('+5511955554444')
      member_manager = role_user('agendamento_manage', 'conversation_manage')
      create(:inbox_member, user: member_manager, inbox: waha)
      {
        admin => 200, member_manager => 200, role_user('agendamento_manage', 'conversation_manage') => 422,
        role_user('agendamento_view') => 401, create(:user, account: account, role: :agent) => 401, role_user('crm_view', 'crm_admin') => 401
      }.each do |user, status|
        Crm::BookingInvite.delete_all
        call(user, :post, path, phone: '+5511955554444')
        expect(response.status).to eq(status), "#{user.id}: #{response.status} #{response.body}"
      end
    end
  end
end
