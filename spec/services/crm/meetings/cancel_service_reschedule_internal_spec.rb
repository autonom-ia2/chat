require 'rails_helper'

# Reunião interna (#1188) cancela e remarca pelos serviços existentes, sem chamar provedor.
RSpec.describe Crm::Meetings::CancelService do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:meeting_params) do
    { title: 'Conversa', starts_at: starts_at, ends_at: starts_at + 30.minutes, timezone: 'America/Sao_Paulo',
      extra_guests: [], location_type: 'whatsapp_video' }
  end
  let(:meeting) do
    Crm::Meetings::InternalCreator.new(account: account, card: world.card, inbox: nil, scheduled_by: world.host, params: meeting_params).perform
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    allow(Google::CalendarEventService).to receive(:new)
    allow(Microsoft::CalendarEventService).to receive(:new)
  end

  it 'cancela, cancela o lembrete e registra a atividade sem provedor' do
    result = described_class.new(meeting: meeting).perform

    expect(result.status).to eq('canceled')
    expect(result.reminder.status).to eq('canceled')
    expect(Crm::Activity.where(card_id: world.card.id, event_type: 'meeting_canceled').count).to eq(1)
    expect(Google::CalendarEventService).not_to have_received(:new)
    expect(Microsoft::CalendarEventService).not_to have_received(:new)
  end

  it 'remarca, rearma o lembrete e mantém o convidado só de telefone' do
    new_start = starts_at + 1.day

    result = Crm::Meetings::RescheduleService.new(meeting: meeting, params: { starts_at: new_start, ends_at: new_start + 30.minutes }).perform

    expect(result).to have_attributes(status: 'scheduled', starts_at: new_start, ends_at: new_start + 30.minutes, provider: 'internal')
    expect(result.reminder).to have_attributes(due_at: new_start - 15.minutes, status: 'pending')
    expect(result.meeting_guests.pluck(:phone_number)).to eq(['+5511912345678'])
    expect(Crm::Activity.where(card_id: world.card.id, event_type: 'meeting_rescheduled').count).to eq(1)
    expect(Google::CalendarEventService).not_to have_received(:new)
  end
end
