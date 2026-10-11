require 'rails_helper'

# Marcar pela agenda no painel (#1265): páginas que servem, horários livres e a reunião marcada pela atendente pelo
# mesmo Booker da página pública (mesmo card, horário ocupado recusado, avisos só com "Avisar o cliente").
RSpec.describe 'Api::V1::Accounts::Crm::BookingPageMeetings', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }
  let(:slot) { '2026-10-20T10:00:00-03:00' }
  let(:notice_inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    world.card.update!(inbox: inbox)
    create(:inbox_member, user: world.host, inbox: inbox)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  def book(user = world.host, **extra)
    call(user, :post, "#{base}/#{world.profile.id}/meetings", { card_id: world.card.id, starts_at: slot }.merge(extra))
  end

  describe 'GET bookable' do
    it 'lists the published pages with durations, locations and notices' do
      world.profile.update!(notice_inbox: notice_inbox, slot_durations: [60])
      create_booking_profile(account: account, host: world.host, title: 'Rascunho', enabled: false)

      call(world.host, :get, "#{base}/bookable")

      expect(response).to have_http_status(:ok)
      expect(body['payload']).to eq([{
                                      'id' => world.profile.id, 'title' => 'Conversa de 30 min', 'timezone' => 'America/Sao_Paulo',
                                      'duration_minutes' => 30, 'durations' => [30, 60], 'notices' => true,
                                      'locations' => [{ 'type' => 'whatsapp_video', 'label' => 'Vídeo no WhatsApp',
                                                        'needs_email' => false }]
                                    }])
    end
  end

  describe 'GET slots' do
    it 'returns the free starts of the day by the public page rule' do
      create_internal_meeting(world: world, starts_at: Time.zone.parse(slot))

      call(world.host, :get, "#{base}/#{world.profile.id}/slots", { date: '2026-10-20' })

      expect(response).to have_http_status(:ok)
      slots = body.dig('payload', 'slots')
      expect(slots).to include('2026-10-20T09:00:00-03:00', '2026-10-20T11:00:00-03:00')
      expect(slots).not_to include(slot)
      expect(body.dig('payload', 'next_slot')).to be_nil
    end

    it 'points to the next free start when the day has none' do
      call(world.host, :get, "#{base}/#{world.profile.id}/slots", { date: '2026-10-18' })

      expect(body.dig('payload', 'slots')).to eq([])
      expect(body.dig('payload', 'next_slot')).to be_present
    end
  end

  describe 'POST meetings' do
    it 'books into the card of the client, marked as booked by the panel user, and returns the meeting' do
      expect { book(admin) }.not_to change(Crm::Card, :count)

      expect(response).to have_http_status(:created)
      meeting = Crm::Meeting.sole
      expect(meeting).to have_attributes(card_id: world.card.id, created_by_id: world.host.id, source: 'panel', status: 'scheduled')
      expect(meeting.starts_at).to eq(Time.zone.parse(slot))
      expect(meeting.metadata).to include('booking_profile_id' => world.profile.id, 'booked_by_user_id' => admin.id)
      invite = Crm::BookingInvite.sole
      expect(invite).to have_attributes(channel: 'panel', meeting_id: meeting.id, created_by_id: admin.id, contact_id: world.contact.id)
      expect(body['payload']).to include('id' => meeting.id, 'card_id' => world.card.id, 'source' => 'panel',
                                         'manage_url' => invite.url, 'notice_will_send' => false)
    end

    it 'refuses a taken start with 409 and creates nothing' do
      create_internal_meeting(world: world, starts_at: Time.zone.parse(slot))

      expect { book }.not_to change(Crm::Meeting, :count)

      expect(response).to have_http_status(:conflict)
      expect(body['error']).to eq('crm.booking_v2.slot_unavailable')
    end

    it 'refuses a start outside the page hours' do
      book(starts_at: '2026-10-20T03:00:00-03:00')

      expect(response).to have_http_status(:conflict)
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'schedules the WhatsApp notices only when asked to notify' do
      world.profile.update!(notice_inbox: notice_inbox)

      book(notify: false)
      expect(Crm::MeetingNotice.count).to eq(0)
      expect(Crm::Meeting.sole.metadata).not_to have_key('notice_basis')

      book(starts_at: '2026-10-21T10:00:00-03:00', notify: true)
      meeting = Crm::Meeting.order(:id).last
      expect(meeting.notices.pluck(:kind)).to include('booked')
      # #1271: com o aviso, fica o motivo de mandar mensagem a quem não marcou sozinho.
      expect(meeting.metadata).to include('notice_basis' => 'combinado_com_atendente', 'booked_by_user_id' => world.host.id)
    end

    it 'keeps the client without notices when rescheduled after booking without notify' do
      world.profile.update!(notice_inbox: notice_inbox)
      book(notify: false)
      meeting = Crm::Meeting.sole
      expect(meeting.metadata['notify_client']).to be(false)

      Crm::BookingV2::Notices::Scheduler.meeting_moved!(meeting)

      expect(Crm::MeetingNotice.count).to eq(0)
    end

    it 'refuses a closed card instead of booking into another one' do
      world.card.update!(status: :won)

      expect { book(admin) }.not_to change(Crm::Card, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.card_closed')
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'books from the contact alone into the open card of the contact' do
      call(world.host, :post, "#{base}/#{world.profile.id}/meetings", { contact_id: world.contact.id, starts_at: slot })

      expect(response).to have_http_status(:created)
      expect(Crm::Meeting.sole.card_id).to eq(world.card.id)
    end

    it 'returns the same meeting for the same request_id' do
      book(request_id: 'panel-request-0001')
      first = body.dig('payload', 'id')

      book(request_id: 'panel-request-0001')

      expect(response).to have_http_status(:ok)
      expect(body.dig('payload', 'id')).to eq(first)
      expect(Crm::Meeting.count).to eq(1)
      expect(Crm::BookingInvite.count).to eq(1)
    end

    it 'refuses a client without a valid phone' do
      world.contact.update!(phone_number: nil)

      book

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.invalid_phone')
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'refuses a card without contact' do
      world.card.update!(contact: nil)

      book(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body['error']).to eq('crm.booking_v2.no_contact')
    end

    it 'answers 404 for a page that is not published' do
      world.profile.update!(enabled: false)

      book

      expect(response).to have_http_status(:not_found)
      expect(body['error']).to eq('crm.booking_v2.no_page')
    end
  end

  describe 'permissions' do
    def role_user(*permissions)
      user = create(:user, account: account, role: :agent)
      role = create(:custom_role, account: account, permissions: permissions)
      user.account_users.find_by(account: account).update!(custom_role: role)
      create(:inbox_member, user: user, inbox: inbox)
      user
    end

    it 'denies who cannot attend by the scheduling (role without CRM) on every route' do
      no_crm = role_user('conversation_manage')

      call(no_crm, :get, "#{base}/bookable")
      expect(response).to have_http_status(:unauthorized)

      book(no_crm)
      expect(response).to have_http_status(:unauthorized)
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'denies an agent who cannot see the card' do
      outsider = create(:user, account: account, role: :agent)

      book(outsider)

      expect(response).to have_http_status(:unauthorized)
      expect(Crm::Meeting.count).to eq(0)
    end

    it 'answers 404 on every route when the account flag is off' do
      account.disable_features('crm_booking_v2')
      account.save!

      [[:get, "#{base}/bookable"], [:get, "#{base}/#{world.profile.id}/slots"], [:post, "#{base}/#{world.profile.id}/meetings"]].each do |verb, path|
        call(admin, verb, path, { card_id: world.card.id, starts_at: slot })
        expect(response).to have_http_status(:not_found)
        expect(body['error']).to eq('crm.booking_v2.disabled')
      end
    end
  end
end
