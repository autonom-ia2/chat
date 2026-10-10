require 'rails_helper'

RSpec.describe Crm::Meeting, type: :model do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { 2.days.from_now.change(min: 0) }

  describe 'reunião interna (sem Google/Microsoft)' do
    it 'agenda sem caixa de e-mail e com cliente só com WhatsApp' do
      meeting = create_internal_meeting(world: world, starts_at: starts_at)

      expect(meeting).to be_persisted
      expect(meeting.inbox).to be_nil
      expect(meeting).to be_internal
      expect(meeting).to be_whatsapp_video
      expect(meeting.meeting_guests.first.email).to be_nil
    end

    it 'recusa quando ninguém tem e-mail nem telefone' do
      contact = account.contacts.create!(name: 'Sem contato')
      card = create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: contact)
      meeting = account.crm_meetings.new(card: card, created_by: world.host, title: 'x', provider: :internal,
                                         online_meeting_type: :whatsapp_video, timezone: 'UTC',
                                         starts_at: starts_at, ends_at: starts_at + 30.minutes)

      expect(meeting).not_to be_valid
      expect(meeting.errors[:base]).to include('at least one reachable guest (email or phone) is required')
    end

    it 'aceita só link http ou https no link do agente' do
      ok = create_internal_meeting(world: world, starts_at: starts_at, online_meeting_type: :custom_link,
                                   online_meeting_url: 'https://meet.example.com/sala')
      expect(ok).to be_valid

      %w[javascript:alert(1) data:text/html,x ftp://x.example.com].each do |url|
        bad = ok.dup
        bad.online_meeting_url = url
        expect(bad).not_to be_valid, "#{url} deveria ser recusado"
        expect(bad.errors[:online_meeting_url]).to include('must be an http or https URL')
      end
    end

    it 'recusa link do agente maior que o limite' do
      meeting = create_internal_meeting(world: world, starts_at: starts_at)
      meeting.assign_attributes(online_meeting_type: :custom_link, online_meeting_url: "https://x.example.com/#{'a' * 600}")

      expect(meeting).not_to be_valid
    end
  end

  describe 'reunião de calendário (Google/Microsoft) continua exigindo o que exigia' do
    it 'exige caixa com calendário habilitado' do
      meeting = account.crm_meetings.new(card: world.card, created_by: world.host, title: 'x', provider: :google,
                                         online_meeting_type: :google_meet, timezone: 'UTC',
                                         starts_at: starts_at, ends_at: starts_at + 30.minutes,
                                         inbox: create_crm_inbox(account: account))

      expect(meeting).not_to be_valid
      expect(meeting.errors[:inbox]).to include('must have calendar enabled')
    end

    it 'exige caixa (inbox) para quem não é interna' do
      meeting = account.crm_meetings.new(card: world.card, created_by: world.host, title: 'x', provider: :google,
                                         timezone: 'UTC', starts_at: starts_at, ends_at: starts_at + 30.minutes)

      expect(meeting).not_to be_valid
      expect(meeting.errors[:inbox_id]).to be_present
    end

    it 'exige convidado com e-mail (o convite sai pelo provedor)' do
      contact = create_booking_contact(account: account, phone: '+5511900001111')
      card = create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: contact)
      meeting = account.crm_meetings.new(card: card, created_by: world.host, title: 'x', provider: :google,
                                         timezone: 'UTC', starts_at: starts_at, ends_at: starts_at + 30.minutes,
                                         inbox: create_crm_inbox(account: account))
      meeting.valid?

      expect(meeting.errors[:base]).to include('at least one email-reachable guest is required')
    end
  end

  describe 'enums' do
    it 'mantém os inteiros existentes e acrescenta os novos' do
      expect(described_class.providers).to eq('microsoft' => 0, 'google' => 1, 'internal' => 2)
      expect(described_class.online_meeting_types).to include(
        'teams' => 0, 'google_meet' => 1, 'no_online' => 2,
        'whatsapp_video' => 3, 'whatsapp_voice' => 4, 'custom_link' => 5, 'in_person' => 6
      )
    end
  end
end
