require 'rails_helper'

RSpec.describe Crm::BookingV2::PageTemplates do
  it 'offers exactly the template keys the model accepts' do
    expect(described_class.keys).to match_array(Crm::AgentBookingProfile::TEMPLATE_KEYS)
  end

  it 'prefills sales_30 as a 30-minute WhatsApp video call on weekday business hours' do
    attributes = described_class.attributes_for('sales_30', locale: :pt_BR)

    expect(attributes).to include(
      template_key: 'sales_30', duration_minutes: 30, buffer_minutes: 10, min_notice_minutes: 120, booking_window_days: 14,
      locations: [{ 'type' => 'whatsapp_video' }],
      working_hours: { 'start_hour' => 9, 'end_hour' => 17, 'weekdays' => [1, 2, 3, 4, 5] },
      title: 'Conversa de vendas de 30 min'
    )
  end

  it 'prefills consult_45 and visit_60 as in-person meetings' do
    expect(described_class.attributes_for('consult_45')).to include(duration_minutes: 45, locations: [{ 'type' => 'in_person' }])
    expect(described_class.attributes_for('visit_60')).to include(duration_minutes: 60, locations: [{ 'type' => 'in_person' }])
  end

  it 'starts blank with no location, so publishing asks for one' do
    expect(described_class.attributes_for('blank', locale: :en)).to include(locations: [], title: 'New booking page')
  end

  it 'falls back to English for a locale without the catalog' do
    expect(described_class.attributes_for('visit_60', locale: :de)[:title]).to eq('60-minute visit')
  end

  it 'returns a fresh copy every time (no shared mutable state)' do
    first = described_class.attributes_for('sales_30')
    first[:locations] << { 'type' => 'in_person' }

    expect(described_class.attributes_for('sales_30')[:locations]).to eq([{ 'type' => 'whatsapp_video' }])
  end

  it 'raises on an unknown template' do
    expect { described_class.attributes_for('vip') }.to raise_error(described_class::UnknownTemplate)
  end
end
