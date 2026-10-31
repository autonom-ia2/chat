require 'rails_helper'

# #1479 F3: o job que converte o endereço presencial da página em coordenada, pelo Google Places da plataforma
# (`ConversaCanal::BuscaDeLugar`). Grava só latitude e longitude, no item cujo endereço ainda é o mesmo. Google fora:
# nada gravado e no máximo uma nova tentativa. O log leva o id da página e o status, nunca o endereço.
RSpec.describe Crm::BookingV2::GeocodificarLocaisJob do
  include ActiveJob::TestHelper

  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') } }
  let(:host) { create(:user, account: account, role: :agent) }
  let(:centro) { { 'type' => 'in_person', 'label' => 'Unidade Centro', 'address' => 'Rua Direita, 100', 'extra' => 'fica' } }
  let(:video) { { 'type' => 'whatsapp_video' } }
  let!(:pagina) { create_booking_profile(account: account, host: host, locations: [video, centro], contact_phone: '+551140000473') }
  let(:busca) { instance_double(ConversaCanal::BuscaDeLugar) }
  let(:lugar) { { place_id: 'ChIJ123', nome: 'Rua Direita', endereco: 'Rua Direita, 100', latitude: -23.5489, longitude: -46.6388 } }
  let(:erro_do_google) { Autonomia::Prospecting::SearchRunner::ProviderError }
  let(:logs) { [] }

  before do
    allow(ConversaCanal::BuscaDeLugar).to receive_messages(configurada?: true, para: busca)
    allow(busca).to receive(:suggestions).and_return([{ text: 'Rua Direita, 100', place_id: 'ChIJ123' }])
    allow(busca).to receive(:details).with('ChIJ123').and_return(lugar)
    %i[info warn error].each do |nivel|
      allow(Rails.logger).to receive(nivel).and_call_original
      allow(Rails.logger).to receive(nivel).with(a_string_including('geocodificar')) { |linha| logs << linha }
    end
  end

  it 'grava só latitude e longitude no item do endereço; o resto da lista e do item fica' do
    described_class.perform_now(pagina.id)

    expect(pagina.reload.locations).to eq([video, centro.merge('latitude' => -23.5489, 'longitude' => -46.6388)])
    expect(busca).to have_received(:suggestions).with('Rua Direita, 100')
  end

  it 'o endereço mudou enquanto o job rodava: não grava' do
    allow(busca).to receive(:details) do
      pagina.update_column(:locations, [video, centro.merge('address' => 'Rua Nova, 1')]) # rubocop:disable Rails/SkipsModelValidations
      lugar
    end
    described_class.perform_now(pagina.id)

    expect(pagina.reload.locations.last).to eq(centro.merge('address' => 'Rua Nova, 1'))
  end

  it 'Google falhou: nada gravado, no máximo duas tentativas, sem levantar' do
    allow(busca).to receive(:suggestions).and_raise(erro_do_google, 'O Google não respondeu')

    expect { perform_enqueued_jobs { described_class.perform_later(pagina.id) } }.not_to raise_error

    expect(busca).to have_received(:suggestions).twice
    expect(pagina.reload.locations.last).not_to have_key('latitude')
  end

  it 'sem resultado: nada gravado' do
    allow(busca).to receive(:suggestions).and_return([])
    described_class.perform_now(pagina.id)
    expect(pagina.reload.locations.last).to eq(centro)
  end

  it 'detalhe sem coordenada numérica: nada gravado' do
    allow(busca).to receive(:details).and_return(lugar.merge(latitude: nil))
    described_class.perform_now(pagina.id)
    expect(pagina.reload.locations.last).to eq(centro)
  end

  it 'sem a chave do Google configurada: nada, nem chamada' do
    allow(ConversaCanal::BuscaDeLugar).to receive(:configurada?).and_return(false)
    described_class.perform_now(pagina.id)
    expect(busca).not_to have_received(:suggestions)
  end

  it 'conta desligada: nada' do
    account.disable_features!('agentes_enviar_local_e_contato')
    described_class.perform_now(pagina.id)
    expect(busca).not_to have_received(:suggestions)
  end

  it 'item que já tem coordenada não é buscado de novo' do
    described_class.perform_now(pagina.id)
    described_class.perform_now(pagina.id)
    expect(busca).to have_received(:suggestions).once
  end

  it 'o log leva o id e o status, nunca o endereço' do
    described_class.perform_now(pagina.id)
    allow(busca).to receive(:suggestions).and_raise(erro_do_google, 'O Google não respondeu')
    pagina.update_column(:locations, [centro]) # rubocop:disable Rails/SkipsModelValidations
    perform_enqueued_jobs { described_class.perform_later(pagina.id) }

    expect(logs).not_to be_empty
    expect(logs).to all(include("page_id=#{pagina.id}"))
    expect(logs.join).not_to include('Rua Direita')
    expect(logs.join).not_to include('-23.5489')
  end

  it 'página que não existe mais: nada' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
