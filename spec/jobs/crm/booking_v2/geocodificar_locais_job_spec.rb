require 'rails_helper'

# #1479 F3: o job que converte o endereço presencial da página em coordenada, pelo Google Places da plataforma
# (`GeocodificarLocaisJob::Busca`, sobre o `ConversaCanal::BuscaDeLugar`). Grava só latitude e longitude, no item cujo
# endereço ainda é o mesmo, e só quando o tipo do lugar é preciso. Sem resultado preciso: a marca "não achou" do
# endereço, e ele não é pedido de novo. Google fora: conta a falha e desiste no teto. O disparo (`pedir`) é único por
# página e endereços pendentes. O log leva o id da página e o status, nunca o endereço.
RSpec.describe Crm::BookingV2::GeocodificarLocaisJob do
  include ActiveJob::TestHelper

  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') } }
  let(:host) { create(:user, account: account, role: :agent) }
  let(:centro) { { 'type' => 'in_person', 'label' => 'Unidade Centro', 'address' => 'Rua Direita, 100', 'extra' => 'fica' } }
  let(:video) { { 'type' => 'whatsapp_video' } }
  let!(:pagina) { create_booking_profile(account: account, host: host, locations: [video, centro], contact_phone: '+551140000473') }
  let(:busca) { instance_double(Crm::BookingV2::GeocodificarLocaisJob::Busca) }
  let(:lugar) { { latitude: -23.5489, longitude: -46.6388, tipos: %w[street_address], tipo_principal: nil } }
  let(:erro_do_google) { Autonomia::Prospecting::SearchRunner::ProviderError }
  let(:logs) { [] }

  def limpar_redis
    Redis::Alfred.scan_each(match: 'crm:booking_v2:geocodificar:*') { |chave| Redis::Alfred.delete(chave) }
  end

  def hash_de(endereco)
    Digest::SHA256.hexdigest(endereco).first(16)
  end

  def jobs_enfileirados
    enqueued_jobs.count { |item| item[:job] == Crm::BookingV2::GeocodificarLocaisJob }
  end

  before do
    limpar_redis
    clear_enqueued_jobs
    allow(Crm::BookingV2::GeocodificarLocaisJob::Busca).to receive_messages(configurada?: true, para: busca)
    allow(busca).to receive(:suggestions).and_return([{ text: 'Rua Direita, 100', place_id: 'ChIJ123' }])
    allow(busca).to receive(:details).with('ChIJ123').and_return(lugar)
    %i[info warn error].each do |nivel|
      allow(Rails.logger).to receive(nivel).and_call_original
      allow(Rails.logger).to receive(nivel).with(a_string_including('geocodificar')) { |linha| logs << linha }
    end
  end

  after { limpar_redis }

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

  describe 'endereço que o Google não acha' do
    before { allow(busca).to receive(:suggestions).and_return([]) }

    it 'uma chamada só: marca "não achou" com o hash do endereço, e o próximo pedido não enfileira' do
      described_class.perform_now(pagina.id)

      expect(pagina.reload.locations.last).to eq(centro.merge('geo_nao_achou' => hash_de('Rua Direita, 100')))
      limpar_redis
      expect(described_class.pedir(pagina.reload)).to be(false)
      described_class.perform_now(pagina.id)
      expect(busca).to have_received(:suggestions).once
    end

    it 'o endereço mudou: consulta de novo' do
      described_class.perform_now(pagina.id)
      allow(busca).to receive(:suggestions).and_return([{ text: 'Rua Nova, 1', place_id: 'ChIJ123' }])

      pagina.reload.update!(locations: [video, centro.merge('address' => 'Rua Nova, 1')])
      expect(jobs_enfileirados).to eq(1)
      perform_enqueued_jobs

      expect(busca).to have_received(:suggestions).with('Rua Nova, 1')
      expect(pagina.reload.locations.last).to include('latitude' => -23.5489)
      expect(pagina.locations.last).not_to have_key('geo_nao_achou')
    end
  end

  it 'detalhe sem coordenada numérica: marca "não achou"' do
    allow(busca).to receive(:details).and_return(lugar.merge(latitude: nil))
    described_class.perform_now(pagina.id)
    expect(pagina.reload.locations.last).to eq(centro.merge('geo_nao_achou' => hash_de('Rua Direita, 100')))
  end

  it 'resultado impreciso (a rua, sem o número): marca "não achou", sem coordenada' do
    allow(busca).to receive(:details).and_return(lugar.merge(tipos: %w[route], tipo_principal: 'route'))
    described_class.perform_now(pagina.id)
    expect(pagina.reload.locations.last).to eq(centro.merge('geo_nao_achou' => hash_de('Rua Direita, 100')))
  end

  it 'a cidade, mesmo marcada como ponto de interesse: impreciso' do
    allow(busca).to receive(:details).and_return(lugar.merge(tipos: %w[locality political point_of_interest], tipo_principal: 'locality'))
    described_class.perform_now(pagina.id)
    expect(pagina.reload.locations.last).not_to have_key('latitude')
  end

  it 'um estabelecimento (clínica): preciso' do
    allow(busca).to receive(:details).and_return(lugar.merge(tipos: %w[dentist health point_of_interest establishment],
                                                             tipo_principal: 'dentist'))
    described_class.perform_now(pagina.id)
    expect(pagina.reload.locations.last).to include('latitude' => -23.5489)
  end

  describe 'Google fora' do
    before { allow(busca).to receive(:suggestions).and_raise(erro_do_google, 'O Google não respondeu') }

    it 'nada gravado; conta a falha e, no teto (3), desiste com registro e o próximo pedido não enfileira' do
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      3.times do
        expect(described_class.pedir(pagina.reload)).to be(true)
        perform_enqueued_jobs
        Redis::Alfred.scan_each(match: 'crm:booking_v2:geocodificar:trava:*') { |chave| Redis::Alfred.delete(chave) }
      end

      expect(described_class.pedir(pagina.reload)).to be(false)
      expect(busca).to have_received(:suggestions).exactly(3).times
      expect(pagina.reload.locations.last).to eq(centro)
      expect(logs.count { |linha| linha.include?('status=desistiu') }).to eq(1)
      expect(ChatwootExceptionTracker).to have_received(:new).once
    end

    it 'não levanta' do
      expect { described_class.perform_now(pagina.id) }.not_to raise_error
    end
  end

  describe '.pedir' do
    it 'enfileira uma vez por página e endereços pendentes (a trava de 1 hora)' do
      expect(described_class.pedir(pagina)).to be(true)
      expect(described_class.pedir(pagina)).to be(false)
      expect(jobs_enfileirados).to eq(1)
    end

    it 'endereço novo pendente gera trava nova' do
      described_class.pedir(pagina)
      pagina.update_column(:locations, [centro, centro.merge('address' => 'Rua B, 2')]) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.pedir(pagina.reload)).to be(true)
    end

    it 'sem endereço pendente: não enfileira' do
      described_class.perform_now(pagina.id)
      expect(described_class.pedir(pagina.reload)).to be(false)
    end

    it 'conta desligada: não enfileira' do
      account.disable_features!('agentes_enviar_local_e_contato')
      expect(described_class.pedir(pagina.reload)).to be(false)
      expect(jobs_enfileirados).to eq(0)
    end
  end

  it 'sem a chave do Google configurada: nada, nem chamada' do
    allow(described_class::Busca).to receive(:configurada?).and_return(false)
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

  it 'o log leva o id e o status, nunca o endereço nem a coordenada' do
    described_class.perform_now(pagina.id)
    allow(busca).to receive(:suggestions).and_raise(erro_do_google, 'O Google não respondeu')
    pagina.update_column(:locations, [centro]) # rubocop:disable Rails/SkipsModelValidations
    3.times { described_class.perform_now(pagina.id) }

    expect(logs).not_to be_empty
    expect(logs).to all(include("page_id=#{pagina.id}"))
    expect(logs.join).not_to include('Rua Direita')
    expect(logs.join).not_to include('-23.5489')
  end

  it 'página que não existe mais: nada' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  describe Crm::BookingV2::GeocodificarLocaisJob::Busca do
    let(:detalhe) { 'https://places.googleapis.com/v1/places/ChIJ123' }
    let(:corpo) do
      { id: 'ChIJ123', location: { latitude: -23.5, longitude: -46.6 }, types: %w[street_address], primaryType: 'street_address' }.to_json
    end

    before do
      allow(described_class).to receive(:para).and_call_original
      allow(Autonomia::Prospecting::Setting).to receive(:platform_config).and_call_original
      allow(Autonomia::Prospecting::Setting).to receive(:platform_config).with('GOOGLE_PLACES_API_KEY').and_return('chave')
    end

    it 'pede o tipo do lugar no FieldMask e devolve a coordenada, os tipos e o tipo principal' do
      pedido = stub_request(:get, detalhe).with(query: hash_including({}),
                                                headers: { 'X-Goog-FieldMask' => 'id,displayName,formattedAddress,location,types,primaryType' })
                                          .to_return(status: 200, body: corpo)

      lugar = described_class.para(account).details('ChIJ123')

      expect(pedido).to have_been_requested
      expect(lugar).to eq(latitude: -23.5, longitude: -46.6, tipos: %w[street_address], tipo_principal: 'street_address')
    end

    it 'o "+" da conversa (#1702) segue pedindo os campos de sempre' do
      Rails.cache.clear
      pedido = stub_request(:get, detalhe).with(query: hash_including({}),
                                                headers: { 'X-Goog-FieldMask' => 'id,displayName,formattedAddress,location' })
                                          .to_return(status: 200, body: corpo)

      ConversaCanal::BuscaDeLugar.para(account).details('ChIJ123')

      expect(pedido).to have_been_requested
    end
  end
end
