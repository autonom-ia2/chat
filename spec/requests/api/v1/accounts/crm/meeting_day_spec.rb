require 'rails_helper'

# Dia da reunião pela API (#1193, F2-B): detalhe com o cliente (J4-A1/A2), "Lembrar" (J4-A5), link para remarcar
# (J4-A6), resultado com a oferta de mover o card (J4-A3/A7) e "Depois da reunião" na página (J4-A7). Permissão: ver o
# card e responder a conversa; flag da conta desligada responde 404.
RSpec.describe 'Api::V1::Accounts::Crm meeting day', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:proposal) { create_crm_stage(account: account, pipeline: world.pipeline, name: 'Proposta') }
  let(:meetings) { "/api/v1/accounts/#{account.id}/crm/meetings" }
  let(:upcoming) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'), conversation: conversation,
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let(:finished) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-19T12:00:00Z'), conversation: conversation,
                            metadata: { 'booking_profile_id' => world.profile.id })
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true',
                      'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-19T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.card.update!(inbox: inbox)
    create(:inbox_member, user: world.host, inbox: inbox)
    # Janela de 24 h aberta pelo cliente: o WhatsApp oficial deixa responder.
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def body
    response.parsed_body
  end

  def manage_invite(meeting)
    create_booking_invite(world: world, conversation: conversation, meeting: meeting, scheduled_at: 1.day.ago, channel: 'conversation')
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: inbox)
    user
  end

  describe 'GET show (J4-A1/A2)' do
    it 'returns time, location, the client number, the wa.me link and the WhatsApp conversation the person can open' do
      call(world.host, :get, "#{meetings}/#{upcoming.id}")

      expect(response).to have_http_status(:ok)
      payload = body['payload']
      expect(payload).to include('provider' => 'internal', 'location_type' => 'whatsapp_video', 'inbox_id' => nil,
                                 'starts_at' => '2026-10-20T13:00:00Z', 'confirmation_status' => 'pending', 'reminded_at' => nil)
      expect(payload['client']).to eq('name' => 'Marcos Lima', 'phone' => '+5511912345678',
                                      'whatsapp_url' => 'https://wa.me/5511912345678', 'conversation_id' => conversation.display_id)
      expect(payload['guests'].first).to include('phone_number' => '+5511912345678', 'name' => 'Marcos Lima')
    end

    it 'leaves the conversation out when the person cannot open it, keeping the wa.me link' do
      hidden_inbox = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox
      upcoming.update!(conversation: create(:conversation, account: account, inbox: hidden_inbox, contact: world.contact))
      conversation.destroy!

      call(world.host, :get, "#{meetings}/#{upcoming.id}")

      expect(body['payload']['client']).to include('conversation_id' => nil, 'whatsapp_url' => 'https://wa.me/5511912345678')
    end
  end

  describe 'GET calendar events (J4-A1/A5)' do
    it 'lists the internal meeting of the agent with time, location type and the client status' do
      upcoming.update!(confirmation_status: :change_requested)

      call(world.host, :get, "/api/v1/accounts/#{account.id}/crm/calendar/events",
           { from: '2026-10-20T00:00:00Z', to: '2026-10-21T00:00:00Z' })

      expect(response).to have_http_status(:ok)
      event = body['payload'].find { |item| item['id'] == "meeting_#{upcoming.id}" }
      expect(event).to include('event_type' => 'meeting', 'provider' => 'internal', 'online_meeting_type' => 'whatsapp_video',
                               'inbox_id' => nil, 'starts_at' => '2026-10-20T13:00:00Z', 'ends_at' => '2026-10-20T13:30:00Z',
                               'booking' => true, 'confirmation_status' => 'change_requested', 'assignee_id' => world.host.id)
    end
  end

  describe 'POST remind (J4-A5)' do
    it 'sends the reminder as the person and returns when it was sent' do
      invite = manage_invite(upcoming)

      call(world.host, :post, "#{meetings}/#{upcoming.id}/remind")

      expect(response).to have_http_status(:ok)
      message = conversation.messages.outgoing.last
      expect(body['payload']).to eq('reminded_at' => Time.current.iso8601, 'message_id' => message.id)
      expect(message.content).to include(invite.url)
      expect(message.sender).to eq(world.host)
    end

    it 'refuses with a lay code: stopped notices without link, closed window with the link to copy' do
      invite = manage_invite(upcoming)
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)

      call(world.host, :post, "#{meetings}/#{upcoming.id}/remind")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to eq('error' => 'crm.booking_v2.stopped')

      Crm::BookingNoticeStop.delete_all
      conversation.messages.incoming.each { |message| message.update!(created_at: 2.days.ago) }
      call(world.host, :post, "#{meetings}/#{upcoming.id}/remind")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to eq('error' => 'crm.booking_v2.cannot_reply', 'url' => invite.url)
      expect(conversation.messages.outgoing.count).to eq(0)
    end

    it 'hides the meeting from someone who cannot see the card, and answers 404 with the flag off' do
      manage_invite(upcoming)
      blind = create(:user, account: account, role: :agent)

      call(blind, :post, "#{meetings}/#{upcoming.id}/remind")
      expect(response).to have_http_status(:not_found)

      account.disable_features('crm_booking_v2')
      account.save!
      call(admin, :post, "#{meetings}/#{upcoming.id}/remind")
      expect(response).to have_http_status(:not_found)
      expect(body['error']).to eq('crm.booking_v2.disabled')
      expect(conversation.messages.outgoing.count).to eq(0)
    end

    it 'gives the link to copy when no conversation of the client is one the person can reply to' do
      hidden_inbox = create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox
      hidden = create(:conversation, account: account, inbox: hidden_inbox, contact: world.contact)
      upcoming.update!(conversation: hidden)
      invite = manage_invite(upcoming)
      invite.update!(conversation: hidden)
      conversation.destroy!

      call(world.host, :post, "#{meetings}/#{upcoming.id}/remind")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to eq('error' => 'crm.booking_v2.no_conversation', 'url' => invite.url)
      expect(hidden.messages.count).to eq(0)
    end
  end

  describe 'POST rebook_link (J4-A6)' do
    it 'sends a new link after a no-show and returns the invite' do
      call(world.host, :post, "#{meetings}/#{finished.id}/record_outcome", { meeting: { outcome: 'no_show' } })
      expect(response).to have_http_status(:ok)
      expect(conversation.messages.outgoing.count).to eq(0)

      call(world.host, :post, "#{meetings}/#{finished.id}/rebook_link")

      expect(response).to have_http_status(:ok)
      invite = Crm::BookingInvite.find(body['payload']['id'])
      expect(body['payload']).to include('state' => 'sent', 'url' => invite.url)
      expect(conversation.messages.outgoing.last.content).to include(invite.url)
    end

    it 'refuses before a no-show and denies a role without CRM' do
      call(world.host, :post, "#{meetings}/#{finished.id}/rebook_link")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(body).to eq('error' => 'crm.booking_v2.not_rebookable')

      finished.update!(outcome: :no_show, outcome_recorded_at: Time.current)
      no_crm = role_user('conversation_manage')
      call(no_crm, :post, "#{meetings}/#{finished.id}/rebook_link")
      expect(response).to have_http_status(:unauthorized)
      expect(Crm::BookingInvite.count).to eq(0)
    end
  end

  describe 'POST record_outcome (J4-A3/A7)' do
    it 'records held, updates the card history and asks to move the card when the page asks' do
      world.profile.update!(post_meeting_mode: 'ask', post_meeting_stage: proposal)

      call(world.host, :post, "#{meetings}/#{finished.id}/record_outcome", { meeting: { outcome: 'held' } })

      expect(response).to have_http_status(:ok)
      expect(body['payload']).to include('outcome' => 'held')
      expect(body['post_meeting']).to eq('mode' => 'ask', 'moved' => false,
                                         'stage' => { 'id' => proposal.id, 'name' => 'Proposta', 'pipeline_id' => world.pipeline.id })
      expect(world.card.activities.where(event_type: 'meeting_outcome_recorded').count).to eq(1)
      expect(world.card.reload.stage_id).to eq(world.stage.id)
    end

    it 'moves by itself in auto mode, and returns no offer for an ordinary meeting' do
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)

      call(world.host, :post, "#{meetings}/#{finished.id}/record_outcome", { meeting: { outcome: 'held' } })
      expect(body['post_meeting']).to include('mode' => 'auto', 'moved' => true)
      expect(world.card.reload.stage_id).to eq(proposal.id)

      plain = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-19T10:00:00Z'))
      call(world.host, :post, "#{meetings}/#{plain.id}/record_outcome", { meeting: { outcome: 'held' } })
      expect(response).to have_http_status(:ok)
      expect(body['post_meeting']).to be_nil
    end
  end

  describe 'booking page post_meeting (J4-A7)' do
    let(:page_path) { "/api/v1/accounts/#{account.id}/crm/booking_pages/#{world.profile.id}" }

    it 'saves mode and stage, and shows them back' do
      call(admin, :patch, page_path, { booking_page: { post_meeting: { mode: 'auto', stage_id: proposal.id } } })

      expect(response).to have_http_status(:ok)
      expect(body['payload']['post_meeting']).to eq('mode' => 'auto', 'stage_id' => proposal.id, 'pipeline_id' => world.pipeline.id)
      expect(world.profile.reload).to have_attributes(post_meeting_mode: 'auto', post_meeting_stage_id: proposal.id)

      call(admin, :patch, page_path, { booking_page: { post_meeting: { stage_id: '' } } })
      expect(body['payload']['post_meeting']).to eq('mode' => 'auto', 'stage_id' => nil, 'pipeline_id' => nil)
    end

    it 'refuses an unknown mode, a stage of another account, of an archived pipeline or that is not a number' do
      other_account = create(:account)
      _other_pipeline, foreign_stage = create_crm_pipeline(account: other_account, user: admin)
      archived_pipeline, archived_stage = create_crm_pipeline(account: account, user: admin, name: 'Antigo')
      archived_pipeline.update!(status: :archived)

      [{ mode: 'always' }, { stage_id: foreign_stage.id }, { stage_id: archived_stage.id }, { stage_id: 'abc' }].each do |post_meeting|
        call(admin, :patch, page_path, { booking_page: { post_meeting: post_meeting } })
        expect(response).to have_http_status(:unprocessable_entity), "#{post_meeting}: #{response.status}"
      end
      expect(world.profile.reload).to have_attributes(post_meeting_mode: 'ask', post_meeting_stage_id: nil)
    end

    it 'does not let a person who only views the pages change it' do
      viewer = role_user('agendamento_view', 'crm_view')

      call(viewer, :patch, page_path, { booking_page: { post_meeting: { mode: 'auto', stage_id: proposal.id } } })

      expect(response).to have_http_status(:unauthorized)
      expect(world.profile.reload.post_meeting_stage_id).to be_nil
    end
  end
end
