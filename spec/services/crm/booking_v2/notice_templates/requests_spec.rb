require 'rails_helper'

# Estado dos pedidos de modelo de aviso de uma página (#1272): "enviando" só uma vez, junta com o que a Meta diz,
# "enviando" esquecido vira falha.
RSpec.describe Crm::BookingV2::NoticeTemplates::Requests do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:page) { create_booking_profile(account: account, host: create(:user, account: account, role: :administrator)) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:requests) { described_class.new(page: page, inbox: inbox) }

  before { channel.update_columns(message_templates: []) } # rubocop:disable Rails/SkipsModelValidations

  it 'marca "enviando" e não marca de novo enquanto houver envio em andamento (clique duplo)' do
    expect(requests.start!(%w[booked day_before x])).to eq(%w[booked day_before])
    expect(requests.start!(%w[booked hour_before])).to eq([])
    expect(requests.states.keys).to eq(%w[booked day_before])
  end

  it 'não pede de novo o que já está na Meta; tenta de novo o que falhou' do
    channel.update_columns(message_templates: [{ 'name' => 'agendamento_ao_marcar_v1', 'language' => 'pt_BR', 'status' => 'PENDING' }]) # rubocop:disable Rails/SkipsModelValidations
    requests.start!(%w[day_before])
    requests.finish!('day_before', error: 'Recusado.')

    expect(requests.start!(%w[booked day_before])).to eq(%w[day_before])
  end

  it 'o que a Meta diz vence a falha antiga; "enviando" vence tudo' do
    requests.start!(%w[booked])
    requests.finish!('booked', error: 'x')
    channel.update_columns(message_templates: [{ 'name' => 'agendamento_ao_marcar_v1', 'language' => 'pt_BR', 'status' => 'APPROVED' }]) # rubocop:disable Rails/SkipsModelValidations

    expect(requests.states['booked']).to include('state' => 'approved', 'name' => 'agendamento_ao_marcar_v1')
  end

  it '"enviando" esquecido há mais de 15 minutos vira falha e pode tentar de novo' do
    requests.start!(%w[booked])

    travel_to(16.minutes.from_now) do
      expect(requests.states['booked']['state']).to eq('failed')
      expect(requests.start!(%w[booked])).to eq(%w[booked])
    end
  end

  it 'pedidos de outra caixa não contam' do
    requests.start!(%w[booked])
    other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox

    expect(described_class.new(page: page, inbox: other).states).to eq({})
  end
end
