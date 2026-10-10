require 'rails_helper'

# O cliente da reunião no dia (#1193, J4-A1/A2): número gravado na reunião, link do WhatsApp sem interpretar texto e
# a conversa de WhatsApp que a pessoa pode abrir, só do mesmo contato.
RSpec.describe Crm::BookingV2::MeetingClient do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:whatsapp) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
  let(:widget) { create(:inbox, account: account) }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: 1.day.from_now, metadata: { 'booking_profile_id' => world.profile.id })
  end

  def conversation_in(inbox, contact: world.contact, at: Time.current)
    create(:conversation, account: account, inbox: inbox, contact: contact, last_activity_at: at)
  end

  it 'uses the number the client gave for the meeting and builds the wa.me link from its digits' do
    meeting.meeting_guests.first.update!(phone_number: '+5511988887777')

    client = described_class.new(meeting.reload)

    expect(client.phone).to eq('+5511988887777')
    expect(client.whatsapp_url).to eq('https://wa.me/5511988887777')
  end

  it 'falls back to the contact number and has no link without any number' do
    meeting.meeting_guests.first.update!(phone_number: nil, email: 'marcos@example.com')
    expect(described_class.new(meeting.reload).whatsapp_url).to eq('https://wa.me/5511912345678')

    world.contact.update!(phone_number: nil, email: 'marcos@example.com')
    client = described_class.new(meeting.reload)
    expect([client.phone, client.whatsapp_url]).to eq([nil, nil])
  end

  it 'prefers the meeting conversation, then the newest WhatsApp conversation of the contact, and only WhatsApp for the call' do
    widget_conversation = conversation_in(widget)
    old_whatsapp = conversation_in(whatsapp, at: 2.days.ago)
    new_whatsapp = conversation_in(whatsapp, at: 1.hour.ago)
    meeting.update!(conversation: widget_conversation)

    client = described_class.new(meeting.reload)

    expect(client.reply_conversation).to eq(widget_conversation)
    expect(client.whatsapp_conversation).to eq(new_whatsapp)
    expect(client.as_json).to eq(name: 'Marcos Lima', phone: '+5511912345678', whatsapp_url: 'https://wa.me/5511912345678',
                                 conversation_id: new_whatsapp.display_id)
    expect(old_whatsapp).to be_persisted
  end

  it 'skips conversations the person cannot see and never offers another contact conversation' do
    stranger = create_booking_contact(account: account, name: 'Outra', phone: '+5511966665555')
    conversation_in(whatsapp, contact: stranger, at: Time.current)
    hidden = conversation_in(whatsapp, at: 1.hour.ago)
    seen = conversation_in(whatsapp, at: 3.hours.ago)

    client = described_class.new(meeting.reload, visible: ->(conversation) { conversation.id != hidden.id })

    expect(client.whatsapp_conversation).to eq(seen)
    expect(described_class.new(meeting.reload, visible: ->(_conversation) { false }).as_json[:conversation_id]).to be_nil
  end

  it 'writes in the first conversation the channel lets the person answer now, and keeps the first seen when none can' do
    closed_channel = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '12' })
    closed = conversation_in(closed_channel.inbox)
    open_chat = conversation_in(widget)
    meeting.update!(conversation: closed)
    world.card.update!(primary_conversation: open_chat)

    expect(described_class.new(meeting.reload).reply_conversation).to eq(open_chat)

    only_closed = described_class.new(meeting.reload, visible: ->(conversation) { conversation.id == closed.id })
    expect(only_closed.reply_conversation).to eq(closed)
  end

  it 'knows when the client does not want active messages: opt-out, stop of the page notices or of this meeting' do
    expect(described_class.new(meeting).stopped?).to be(false)

    world.contact.update!(opted_out_at: Time.current)
    expect(described_class.new(meeting.reload).stopped?).to be(true)

    world.contact.update!(opted_out_at: nil)
    Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
    expect(described_class.new(meeting.reload).stopped?).to be(true)

    Crm::BookingNoticeStop.delete_all
    meeting.update!(reminders_stopped_at: Time.current)
    expect(described_class.new(meeting.reload).stopped?).to be(true)
  end

  it 'treats official WhatsApp and the WAHA API channel as WhatsApp, not a website chat or a plain API channel' do
    waha = create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' })
    plain_api = create(:channel_api, account: account)

    expect(described_class.whatsapp_inbox?(whatsapp)).to be(true)
    expect(described_class.whatsapp_inbox?(widget)).to be(false)
    expect(described_class.whatsapp_inbox?(nil)).to be(false)
    expect(described_class.whatsapp_inbox?(waha.inbox)).to be(true)
    expect(described_class.whatsapp_inbox?(plain_api.inbox)).to be(false)
  end
end
