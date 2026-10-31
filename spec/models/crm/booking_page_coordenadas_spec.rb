require 'rails_helper'

# #1479 F3: a coordenada de cada local presencial da página é do servidor. Ela segue o endereço: o endereço mudou ou
# saiu, a coordenada sai; o formulário que não a manda (ele só conhece tipo, rótulo, endereço e link) não a apaga.
# Endereço novo sem coordenada enfileira o job que a busca no Google, depois do commit e só com a conta ligada.
RSpec.describe Crm::BookingPageCoordenadas do
  include ActiveJob::TestHelper

  let(:account) { conta_da_fase2.tap { |conta| conta.enable_features!('agentes_enviar_local_e_contato') } }
  let(:host) { create(:user, account: account, role: :agent) }
  let(:centro) { { 'type' => 'in_person', 'label' => 'Unidade Centro', 'address' => 'Rua Direita, 100', 'extra' => 'fica' } }
  let(:video) { { 'type' => 'whatsapp_video', 'label' => 'Vídeo' } }
  let(:job) { Crm::BookingV2::GeocodificarLocaisJob }

  def criar(locations)
    create_booking_profile(account: account, host: host, locations: locations)
  end

  # Como o job grava: só a coluna, sem callbacks.
  def com_coordenada(pagina, endereco, ponto = [-23.5489, -46.6388])
    lista = pagina.reload.locations.map do |item|
      item['address'] == endereco ? item.merge('latitude' => ponto[0], 'longitude' => ponto[1]) : item
    end
    pagina.update_column(:locations, lista) # rubocop:disable Rails/SkipsModelValidations
    pagina.reload
  end

  describe 'enfileirar' do
    it 'endereço novo enfileira o job, com a flag' do
      expect { criar([video, centro]) }.to have_enqueued_job(job)
    end

    it 'sem a flag, não' do
      account.disable_features!('agentes_enviar_local_e_contato')
      expect { criar([video, centro]) }.not_to have_enqueued_job(job)
    end

    it 'sem a Fase 2, não' do
      Autonomia::Agents::Fase2.desligar!(account)
      expect { criar([video, centro]) }.not_to have_enqueued_job(job)
    end

    it 'sem local presencial com endereço, não' do
      expect { criar([video, { 'type' => 'in_person' }]) }.not_to have_enqueued_job(job)
    end

    it 'salvar outra coisa da página não enfileira de novo' do
      pagina = com_coordenada(criar([centro]), centro['address'])
      expect { pagina.update!(title: 'Outro título') }.not_to have_enqueued_job(job)
    end

    it 'erro ao enfileirar não derruba o salvar da página' do
      allow(job).to receive(:perform_later).and_raise(Redis::CannotConnectError)
      expect { criar([centro]) }.not_to raise_error
      expect(Crm::AgentBookingProfile.count).to eq(1)
    end
  end

  describe 'a coordenada segue o endereço' do
    let!(:pagina) { com_coordenada(criar([video, centro]), centro['address']) }

    it 'o formulário salva sem a coordenada (só tipo, rótulo, endereço e link): ela fica' do
      pagina.update!(locations: [video.slice('type', 'label'), centro.except('extra')])
      expect(pagina.reload.locations.last).to include('latitude' => -23.5489, 'longitude' => -46.6388)
    end

    it 'mudou a ordem: a coordenada vai junto do endereço' do
      pagina.update!(locations: [centro, video])
      expect(pagina.reload.locations.first).to include('address' => 'Rua Direita, 100', 'latitude' => -23.5489)
    end

    it 'endereço mudado perde a coordenada e enfileira; o resto do item e da lista fica' do
      novo = centro.merge('address' => 'Rua Nova, 1', 'latitude' => -23.5489, 'longitude' => -46.6388)
      expect { pagina.update!(locations: [video, novo]) }.to have_enqueued_job(job).with(pagina.id)
      expect(pagina.reload.locations).to eq([video, centro.merge('address' => 'Rua Nova, 1')])
    end

    it 'endereço apagado perde a coordenada' do
      sem_endereco = centro.except('address').merge('latitude' => -23.5489, 'longitude' => -46.6388)
      pagina.update!(locations: [video, sem_endereco])
      expect(pagina.reload.locations.last).to eq(centro.except('address'))
    end

    it 'coordenada mandada de fora para um endereço novo não vale' do
      outro = { 'type' => 'in_person', 'address' => 'Rua B, 2', 'latitude' => 1.0, 'longitude' => 2.0 }
      pagina.update!(locations: [video, centro, outro])
      expect(pagina.reload.locations.last).to eq(outro.except('latitude', 'longitude'))
      expect(pagina.locations.second).to include('latitude' => -23.5489)
    end

    it 'outros campos da página ficam como estão' do
      pagina.update!(title: 'Novo', locations: [video, centro.merge('address' => 'Rua Nova, 1')])
      expect(pagina.reload.title).to eq('Novo')
      expect(pagina.locations.first).to eq(video)
    end
  end
end
