require 'rails_helper'

# API do painel de resultados do agendamento (#1194, F2-C): J7-A1 a A5 e J8-A12 por HTTP. Matriz de permissão
# (administrador, gerencia, só vê, agente sem função, função sem o módulo), "meus" x equipe, lista "abriram e não
# marcaram" só com clientes visíveis, "Enviar de novo" que exige o toque e respeita a janela, flag desligada.
RSpec.describe 'Api::V1::Accounts::Crm::BookingStats', type: :request do
  let(:account) { create(:account, locale: 'pt_BR', reporting_timezone: 'America/Sao_Paulo') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:hidden_inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_stats" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') { example.run }
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.card.update!(inbox: inbox)
    create(:inbox_member, user: world.host, inbox: inbox)
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: inbox)
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  def contact_named(name, phone)
    create_booking_contact(account: account, name: name, phone: phone)
  end

  # Cliente que abriu o link e não marcou, com a conversa numa caixa (a da pessoa, por padrão).
  def opened_invite(contact: world.contact, created_by: world.host, conversation_inbox: inbox, opened_at: 1.day.ago, **attrs)
    chat = create(:conversation, account: account, inbox: conversation_inbox, contact: contact)
    Crm::BookingInvite.create!(
      { account: account, booking_profile: world.profile, contact: contact, conversation: chat, created_by: created_by,
        channel: 'conversation', expires_at: 7.days.from_now, sent_at: opened_at - 1.hour, first_opened_at: opened_at,
        open_count: 1 }.merge(attrs)
    )
  end

  describe 'permission matrix (J7-A5, J8-A12)' do
    let(:people) do
      {
        admin: admin,
        manage: role_user('agendamento_manage'),
        view: role_user('agendamento_view'),
        agent: world.host,
        crm_role: role_user('crm_view', 'conversation_manage'),
        no_crm: role_user('conversation_manage')
      }
    end
    # [rota, escopo pedido] => quem passa
    let(:expected) do
      {
        [:stats, 'mine'] => %i[admin manage view agent crm_role],
        [:stats, 'team'] => %i[admin manage view],
        [:list, 'mine'] => %i[admin manage view agent crm_role],
        [:list, 'team'] => %i[admin manage view]
      }
    end

    # Negado = 401 (Pundit::NotAuthorizedError no RequestExceptionHandler do upstream).
    it 'allows exactly the expected person x route x scope and denies the rest with 401' do
      expected.each do |(route, scope), allowed|
        people.each do |who, user|
          path = route == :stats ? base : "#{base}/opened_not_booked"
          call(user, :get, path, { period: 7, scope: scope })
          ok = response.status == (allowed.include?(who) ? 200 : 401)
          expect(ok).to be(true), "#{who} #{route} #{scope}: got #{response.status} #{response.body.first(200)}"
        end
      end
    end

    it 'defaults to the team for whoever can see it and to "mine" for everyone else' do
      { admin => 'team', people[:view] => 'team', world.host => 'mine', people[:crm_role] => 'mine' }.each do |user, scope|
        call(user, :get, base)
        expect(response).to have_http_status(:ok)
        expect(body).to include('scope' => scope, 'can_see_team' => scope == 'team')
        expect(body['period']).to include('days' => 30, 'timezone' => 'America/Sao_Paulo')
      end
    end

    it 'answers 404 on every route when the account flag is off' do
      account.disable_features('crm_booking_v2')
      account.save!
      invite = opened_invite

      [[:get, base], [:get, "#{base}/opened_not_booked"], [:post, "#{base}/opened_not_booked/#{invite.id}/resend"]].each do |verb, path|
        call(admin, verb, path)
        expect(response).to have_http_status(:not_found)
        expect(body['error']).to eq('crm.booking_v2.disabled')
      end
    end

    it 'refuses an unknown period or scope with 422' do
      call(admin, :get, base, { period: 14 })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.invalid_period')

      call(admin, :get, base, { scope: 'everyone' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.invalid_scope')
    end
  end

  describe 'GET booking_stats (J7-A1, J7-A3, J8-A12)' do
    let(:other_host) { role_user('crm_view', 'conversation_manage') }

    before do
      opened_invite
      opened_invite(contact: contact_named('Paula Reis', '+5511988887777'), created_by: other_host)
      create_internal_meeting(world: world, starts_at: 3.days.from_now, source: 'invite')
      create_internal_meeting(world: world, starts_at: 4.days.from_now, source: 'public_link', created_by: other_host)
    end

    it 'gives the team numbers to the admin and only the own numbers to the agent, without personal data' do
      call(admin, :get, base, { period: 7 })
      expect(body['totals']).to eq('sent' => 2, 'opened' => 2, 'booked' => 2, 'confirmed' => 0, 'attended' => 0, 'no_show' => 0)
      expect(body['origins']).to eq([{ 'key' => 'conversation', 'count' => 1 }, { 'key' => 'public_link', 'count' => 1 },
                                     { 'key' => 'contact_request', 'count' => 0 }])
      expect(response.body).not_to include('Paula', world.contact.name, '5511')

      call(world.host, :get, base, { period: 7 })
      expect(body['scope']).to eq('mine')
      expect(body['totals']).to include('sent' => 1, 'opened' => 1, 'booked' => 1)
    end
  end

  describe 'GET opened_not_booked (J7-A4, J8-A12)' do
    it 'lists, newest first, one row per client who opened and did not book, and only clients the person can see' do
      ana = contact_named('Ana Souza', '+5511977776666')
      bia = contact_named('Bia Costa', '+5511966665555')
      oculto = contact_named('Cliente Oculto', '+5511955554444')
      opened_invite(opened_at: 3.days.ago)
      opened_invite(contact: ana, opened_at: 1.day.ago)
      opened_invite(contact: ana, opened_at: 2.days.ago)
      opened_invite(contact: bia, opened_at: 2.hours.ago, scheduled_at: 1.hour.ago) # marcou
      opened_invite(contact: bia, opened_at: 5.hours.ago, canceled_at: 1.hour.ago) # cancelado
      opened_invite(contact: oculto, created_by: admin, conversation_inbox: hidden_inbox, opened_at: 1.hour.ago)
      opened_invite(contact: oculto, opened_at: 40.days.ago) # fora do período
      opened_invite(contact: ana, opened_at: 1.hour.ago, metadata: { 'test' => true })

      call(admin, :get, "#{base}/opened_not_booked", { period: 30 })
      expect(body['payload'].map { |row| row['contact']['name'] }).to eq(['Cliente Oculto', 'Ana Souza', world.contact.name])
      expect(body['meta']).to eq('page' => 1, 'per_page' => 20, 'total' => 3, 'can_resend' => true)

      viewer = role_user('agendamento_view', 'conversation_manage')
      call(viewer, :get, "#{base}/opened_not_booked", { period: 30 })
      expect(body['payload'].map { |row| row['contact']['name'] }).to eq(['Ana Souza', world.contact.name])
      expect(response.body).not_to include('Oculto', '5511')
      # Só vê: a lista não oferece "Enviar de novo", que o POST recusaria (401).
      expect(body['payload'].pluck('can_resend')).to all(be(false))
      expect(body['meta']).to include('can_resend' => false)
    end

    it 'skips a client who booked later through another link' do
      opened_invite(opened_at: 2.days.ago)
      create_booking_invite(world: world, scheduled_at: 1.day.ago)

      call(admin, :get, "#{base}/opened_not_booked", { period: 7 })

      expect(body['payload']).to eq([])
    end

    it 'shows the agent only the links the agent sent, still filtered by what the agent can see' do
      mine = opened_invite
      opened_invite(contact: contact_named('Paula Reis', '+5511988887777'), created_by: admin)

      call(world.host, :get, "#{base}/opened_not_booked", { period: 7, scope: 'mine' })

      expect(body['payload'].pluck('id')).to eq([mine.id])
      expect(body['payload'].first).to include('can_resend' => true, 'resent_at' => nil,
                                               'page' => { 'title' => world.profile.title },
                                               'contact' => { 'name' => world.contact.name },
                                               'sent_by' => { 'name' => world.host.name })
      expect(body['meta']).to include('can_resend' => true)
    end

    it 'pages 20 rows at a time' do
      21.times do |index|
        opened_invite(contact: contact_named("Cliente #{index}", "+55119500#{format('%05d', index)}"), opened_at: (index + 1).hours.ago)
      end

      call(admin, :get, "#{base}/opened_not_booked", { period: 7, page: 2 })

      expect(body['payload'].size).to eq(1)
      expect(body['payload'].first['contact']['name']).to eq('Cliente 20')
      expect(body['meta']).to include('page' => 2, 'total' => 21)
    end
  end

  describe 'POST resend (J7-A4)' do
    let(:invite) { opened_invite(opened_at: 2.days.ago, expires_at: 1.day.ago) }

    def resend(user, target = invite)
      call(user, :post, "#{base}/opened_not_booked/#{target.id}/resend")
    end

    it 'sends a fresh link in the client conversation, as the agent, only when the agent taps' do
      expect { resend(world.host) }.to change { invite.conversation.messages.outgoing.count }.by(1)

      expect(response).to have_http_status(:ok)
      fresh = Crm::BookingInvite.where(contact: world.contact).where.not(id: invite.id).sole
      message = invite.conversation.messages.outgoing.last
      expect(message).to have_attributes(sender: world.host, content: include(fresh.url))
      expect(fresh).to have_attributes(sent_at: be_present, created_by_id: world.host.id, booking_profile_id: world.profile.id)
      expect(body['payload']).to eq('id' => invite.id, 'resent_at' => fresh.sent_at.iso8601)

      call(world.host, :get, "#{base}/opened_not_booked", { period: 7 })
      expect(body['payload'].first).to include('id' => invite.id, 'resent_at' => fresh.sent_at.iso8601)
    end

    it 'respects the messaging window: closed conversation answers 422 and nothing is sent or created' do
      channel = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '12' })
      create(:inbox_member, user: world.host, inbox: channel.inbox)
      closed = opened_invite(conversation_inbox: channel.inbox)

      expect { resend(world.host, closed) }.not_to(change { [Message.count, Crm::BookingInvite.count] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.cannot_reply')
    end

    it 'resends a colleague link that still works as it is: no second active link and the same host' do
      active = opened_invite(opened_at: 2.days.ago)

      expect { resend(admin, active) }.not_to change(Crm::BookingInvite, :count)

      expect(response).to have_http_status(:ok)
      message = active.conversation.messages.outgoing.last
      expect(message).to have_attributes(sender: admin, content: include(active.url))
      expect(active.reload).to have_attributes(created_by_id: world.host.id, canceled_at: nil, sent_at: be_within(5.seconds).of(Time.current))
      expect(active.metadata).to include('delivered_by_id' => admin.id)
    end

    it 'renews an expired colleague link in the name of its author, so the client keeps one link and the same host' do
      expect { resend(admin) }.to change { invite.conversation.messages.outgoing.count }.by(1)

      expect(response).to have_http_status(:ok)
      fresh = Crm::BookingInvite.where(contact: world.contact).where.not(id: invite.id).sole
      expect(fresh).to have_attributes(created_by_id: world.host.id, booking_profile_id: world.profile.id, canceled_at: nil)
      expect(fresh.metadata).to include('delivered_by_id' => admin.id)
      expect(invite.conversation.messages.outgoing.last).to have_attributes(sender: admin, content: include(fresh.url))
    end

    it 'never resends to a client the person cannot see, nor a link of someone else to a plain agent' do
      hidden = opened_invite(created_by: world.host, conversation_inbox: hidden_inbox)
      theirs = opened_invite(created_by: admin)

      expect { resend(world.host, hidden) }.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)

      expect { resend(world.host, theirs) }.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'denies a role without CRM and a viewer that cannot send links' do
      [role_user('conversation_manage'), role_user('agendamento_view')].each do |user|
        expect { resend(user) }.not_to change(Message, :count)
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
