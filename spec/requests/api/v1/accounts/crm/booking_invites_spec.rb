require 'rails_helper'

# API do link por cliente (#1190 F1-C): matriz de permissão J8-A3/A7/A14 por HTTP (criar, listar, entregar,
# cancelar), cliente que a pessoa vê, conversa de outro contato, isolamento entre contas, reaproveitamento do
# convite ativo, entrega com texto editado e flag desligada.
RSpec.describe 'Api::V1::Accounts::Crm::BookingInvites', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_invites" }

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

  def role_user(*permissions, member: true)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: inbox) if member
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  # Convite do responsável (agente sem função), pela conversa.
  def host_invite
    create_booking_invite(world: world, conversation: conversation, channel: 'conversation')
  end

  describe 'permission matrix' do
    let(:people) do
      {
        admin: admin,
        manage: role_user('agendamento_manage', 'crm_view', 'conversation_manage'),
        view: role_user('agendamento_view', 'crm_view', 'conversation_manage'),
        agent: world.host,
        blind: create(:user, account: account, role: :agent),
        no_crm: role_user('conversation_manage')
      }
    end
    let(:routes) { %i[create_card create_conversation index deliver destroy] }
    let(:expected) do
      {
        admin: routes, manage: routes, view: %i[create_card create_conversation index deliver],
        agent: routes, blind: [], no_crm: []
      }
    end

    # Convite novo do responsável a cada chamada: cancelar ou entregar não esconde a rota da pessoa seguinte.
    def route(name)
      invite = host_invite
      {
        create_card: [:post, base, { card_id: world.card.id }],
        create_conversation: [:post, base, { conversation_id: conversation.display_id }],
        index: [:get, base, { card_id: world.card.id }],
        deliver: [:post, "#{base}/#{invite.id}/deliver", { conversation_id: conversation.display_id }],
        destroy: [:delete, "#{base}/#{invite.id}", {}]
      }.fetch(name)
    end

    # Negado = 401: é o que o RequestExceptionHandler do upstream devolve para Pundit::NotAuthorizedError.
    it 'allows exactly the expected routes per person and denies the rest' do
      people.each do |who, user|
        routes.each do |name|
          call(user, *route(name))
          allowed = expected[who].include?(name)
          ok = allowed ? response.status.between?(200, 299) : response.status == 401
          expect(ok).to be(true), "#{who} #{name}: got #{response.status} #{response.body.first(200)}"
        end
      end
    end

    it 'shows every invite of the client to admin and agendamento_view, and only the own ones to a plain agent' do
      mine = host_invite
      someone = role_user('crm_view', 'conversation_manage')
      theirs = create_booking_invite(world: world, created_by: someone)

      { admin => [theirs, mine], people[:view] => [theirs, mine], world.host => [mine] }.each do |user, invites|
        call(user, :get, base, { contact_id: world.contact.id })
        expect(response).to have_http_status(:ok)
        expect(body['payload'].pluck('id')).to eq(invites.map(&:id))
      end
    end

    it 'lets a plain agent cancel only the own invites' do
      other = create_booking_invite(world: world, created_by: admin)

      call(world.host, :delete, "#{base}/#{other.id}")

      expect(response).to have_http_status(:unauthorized)
      expect(other.reload.canceled_at).to be_nil
    end

    it 'denies delivering into a conversation the person cannot reply to' do
      hidden = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: world.contact)

      call(world.host, :post, "#{base}/#{host_invite.id}/deliver", { conversation_id: hidden.display_id })

      expect(response).to have_http_status(:unauthorized)
      expect(hidden.messages.count).to eq(0)
    end

    it 'answers 404 on every route when the account flag is off' do
      account.disable_features('crm_booking_v2')
      account.save!

      routes.each do |name|
        call(admin, *route(name))
        expect(response).to have_http_status(:not_found)
        expect(body['error']).to eq('crm.booking_v2.disabled')
      end
    end
  end

  describe 'POST create' do
    it 'creates the invite with the ready text, state and page, without e-mail or phone' do
      call(world.host, :post, base, { conversation_id: conversation.display_id })

      expect(response).to have_http_status(:created)
      payload = body['payload']
      invite = Crm::BookingInvite.find(payload['id'])
      expect(payload).to include(
        'code' => invite.code, 'url' => "https://app.example.com/b/#{invite.code}", 'state' => 'created',
        'text' => "Oi, Marcos! Escolha o melhor horário para a gente conversar: https://app.example.com/b/#{invite.code}",
        'booking_page' => { 'id' => world.profile.id, 'title' => world.profile.title },
        'contact' => { 'id' => world.contact.id, 'name' => 'Marcos Lima' }, 'sent_at' => nil, 'first_opened_at' => nil,
        'scheduled_at' => nil
      )
      expect(payload['expires_at']).to be_present
      expect(response.body).not_to include(world.contact.phone_number)
      expect(invite).to have_attributes(conversation_id: conversation.id, channel: 'conversation', created_by_id: world.host.id)
    end

    it 'returns the active invite of the same page with 200 instead of creating another' do
      call(world.host, :post, base, { card_id: world.card.id })
      first_id = body.dig('payload', 'id')

      call(world.host, :post, base, { contact_id: world.contact.id })

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'id')).to eq(first_id)
      expect(Crm::BookingInvite.count).to eq(1)
    end

    it 'cancels the previous active invite of the person when another page is requested' do
      previous = create_booking_invite(world: world)
      other_page = create_booking_profile(account: account, host: world.host, title: 'Visita')

      call(world.host, :post, base, { card_id: world.card.id, booking_page_id: other_page.id })

      expect(response).to have_http_status(:created)
      expect(body.dig('payload', 'booking_page', 'id')).to eq(other_page.id)
      expect(previous.reload.canceled_at).to be_present
    end

    it 'creates from the contact alone (ContactPolicy), as a copy link without card or conversation' do
      call(world.host, :post, base, { contact_id: world.contact.id })

      expect(response).to have_http_status(:created)
      invite = Crm::BookingInvite.find(body.dig('payload', 'id'))
      expect(invite).to have_attributes(contact_id: world.contact.id, card_id: nil, conversation_id: nil, channel: 'copy')
    end

    it 'keeps the invite of another person when someone switches page' do
      someone = role_user('crm_view', 'conversation_manage')
      theirs = create_booking_invite(world: world, created_by: someone)
      other_page = create_booking_profile(account: account, host: world.host, title: 'Visita')

      call(world.host, :post, base, { card_id: world.card.id, booking_page_id: other_page.id })

      expect(response).to have_http_status(:created)
      expect(theirs.reload.canceled_at).to be_nil
    end

    it 'refuses a conversation of another contact' do
      stranger = create_booking_contact(account: account, name: 'Outra', phone: '+5511955554444')
      other = create(:conversation, account: account, inbox: inbox, contact: stranger)

      call(world.host, :post, base, { card_id: world.card.id, conversation_id: other.display_id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.invite_invalid')
      expect(Crm::BookingInvite.count).to eq(0)
    end

    it 'answers 404 for a contact, card or conversation of another account' do
      foreign = build_booking_world(account: create(:account))
      foreign_conversation = create(:conversation, account: foreign.account, contact: foreign.contact)

      [{ contact_id: foreign.contact.id }, { card_id: foreign.card.id }, { conversation_id: foreign_conversation.display_id }].each do |params|
        call(admin, :post, base, params)
        expect(response).to have_http_status(:not_found), "#{params}: #{response.status}"
      end
      expect(Crm::BookingInvite.count).to eq(0)
    end

    it 'answers 422 no_page when no page is published' do
      world.profile.update!(enabled: false)

      call(world.host, :post, base, { card_id: world.card.id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.no_page')
    end
  end

  describe 'GET index' do
    it 'lists up to 5 most recent invites of the client with state, and the usable pages' do
      invites = Array.new(6) { |index| create_booking_invite(world: world, created_at: index.hours.ago) }
      invites.first.update!(first_opened_at: Time.current)
      create_booking_profile(account: account, host: world.host, title: 'Pausada', enabled: false)

      call(world.host, :get, base, { conversation_id: conversation.display_id })

      expect(response).to have_http_status(:ok)
      expect(body['payload'].pluck('id')).to eq(invites.first(5).map(&:id))
      expect(body['payload'].first['state']).to eq('opened')
      expect(body['payload'].pluck('usable').uniq).to eq([true])
      expect(body['pages']).to eq([{ 'id' => world.profile.id, 'title' => world.profile.title }])
    end

    it 'marks as not usable an invite whose personal link stopped working, even with the page still open' do
      page = create_booking_profile(account: account, host: world.host, title: 'Equipe')
      Crm::BookingV2::PagePeople.new(page).assign!([world.host.id, create(:user, account: account, role: :agent).id])
      link = page.agent_booking_links.find_by(agent_id: world.host.id)
      invite = create_booking_invite(world: world, booking_profile: page, booking_link: link)
      link.update!(enabled: false)

      call(world.host, :get, base, { card_id: world.card.id })

      expect(body['payload'].find { |item| item['id'] == invite.id }['usable']).to be(false)
    end
  end

  describe 'POST deliver' do
    it 'sends the edited text in the conversation and returns it as the text' do
      invite = host_invite
      text = "Marcos, escolha aqui: #{invite.url}"

      call(world.host, :post, "#{base}/#{invite.id}/deliver", { text: text })

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'text')).to eq(text)
      expect(body.dig('payload', 'state')).to eq('sent')
      message = conversation.messages.last
      expect(message.content).to eq(text)
      expect(message.sender).to eq(world.host)
    end

    it 'answers 422 when the edited text lacks the link or has HTML' do
      invite = host_invite

      ['Sem link', "<script>x</script> #{invite.url}"].each do |text|
        call(world.host, :post, "#{base}/#{invite.id}/deliver", { text: text })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(body['error']).to eq('crm.booking_v2.invite_text_invalid')
      end
      expect(conversation.messages.count).to eq(0)
    end

    it 'answers 422 cannot_reply when the channel window is closed' do
      channel = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '12' })
      create(:inbox_member, user: world.host, inbox: channel.inbox)
      closed = create(:conversation, account: account, inbox: channel.inbox, contact: world.contact)

      call(world.host, :post, "#{base}/#{host_invite.id}/deliver", { conversation_id: closed.display_id })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.cannot_reply')
      expect(closed.messages.count).to eq(0)
    end

    it 'answers 422 when there is no conversation to deliver to' do
      invite = create_booking_invite(world: world)

      call(world.host, :post, "#{base}/#{invite.id}/deliver")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.invite_invalid')
    end
  end

  describe 'DELETE destroy' do
    it 'cancels the invite and answers 404 for an invite of another account' do
      invite = host_invite

      call(world.host, :delete, "#{base}/#{invite.id}")

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'state')).to eq('canceled')

      foreign = create_booking_invite(world: build_booking_world(account: create(:account)))
      call(admin, :delete, "#{base}/#{foreign.id}")
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.canceled_at).to be_nil
    end
  end

  # Link copiado para mandar por outro canal (#1194, RA-19): é o "enviado" de quem não manda pela conversa.
  describe 'POST copied' do
    it 'marks the link as sent once, keeping the first date, and only for whoever can deliver it' do
      invite = host_invite
      travel_to(2.hours.ago) { call(world.host, :post, "#{base}/#{invite.id}/copied") }

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'state')).to eq('sent')
      first = invite.reload.sent_at
      expect(first).to be_within(1.minute).of(2.hours.ago)
      expect(invite.metadata).to include('copied_by_id' => world.host.id)

      call(world.host, :post, "#{base}/#{invite.id}/copied")
      expect(invite.reload.sent_at).to eq(first)

      outsider = create(:user, account: account, role: :agent)
      other = create_booking_invite(world: world, created_by: admin)
      statuses = [outsider, world.host].map do |user|
        call(user, :post, "#{base}/#{other.id}/copied")
        response.status
      end
      expect(statuses).to eq([401, 401])
      expect(other.reload.sent_at).to be_nil
    end

    it 'does not touch a canceled link' do
      invite = host_invite
      invite.update!(canceled_at: Time.current)

      call(world.host, :post, "#{base}/#{invite.id}/copied")

      expect(invite.reload.sent_at).to be_nil
    end
  end
end
