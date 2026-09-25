require 'rails_helper'

RSpec.describe Autonomia::Prospecting::Providers::MockProvider do
  it 'returns deterministic realistic lead attributes' do
    provider = described_class.new(query: 'clinica odontologica', location: 'Curitiba, PR', radius: 5000, limit: 2)

    first_run = provider.search
    second_run = provider.search

    expect(first_run.size).to eq(2)
    expect(first_run).to eq(second_run)
    expect(first_run.first).to include(
      provider: 'mock',
      name: include('Clinica Odontologica'),
      city: 'Curitiba',
      state: 'PR',
      country: 'BR'
    )
    expect(first_run.first[:provider_place_id]).to be_present
    expect(first_run.first[:phone]).to be_present
  end

  it 'supports an empty result scenario' do
    provider = described_class.new(query: 'sem resultados', location: 'Curitiba, PR', radius: 5000, limit: 2)

    expect(provider.search).to eq([])
  end

  # Mesmo contrato do Google Places (#677, E1 frente C): o motor e os filtros leem estes atributos dos dois providers.
  it 'devolve os sinais do lugar coerentes com o payload simulado' do
    leads = described_class.new(query: 'dentista', location: 'Curitiba, PR', radius: 1000, limit: 8).search

    leads.each do |lead|
      photos = lead.dig(:raw_payload, :photos)
      expect(lead).to include(
        has_photos: photos.present?,
        photo_count: photos.size,
        open_now: lead.dig(:raw_payload, :currentOpeningHours, :openNow),
        has_opening_hours: true
      )
      expect(lead[:neighborhood]).to be_present
    end
    expect(leads.map { |lead| lead[:has_photos] }.uniq).to contain_exactly(true, false)
  end

  it 'grava o país da busca no lead' do
    lead = described_class.new(query: 'dentista', location: 'Lisboa', radius: 1000, limit: 1, country: 'PT').search.first

    expect(lead[:country]).to eq('PT')
  end

  # Mesmo contrato de paginação do Google Places (#678): o filtro de quem chama decide quem conta para o pedido, e o
  # provider segue gerando lugares até completar o pedido ou chegar à posição máxima.
  describe 'paginação' do
    let(:provider) { described_class.new(query: 'dentista', location: 'Curitiba, PR', radius: 1000, limit: 5) }

    it 'segue gerando lugares até o filtro completar o pedido' do
      results = provider.search { |attributes, _rank| attributes[:has_photos] }

      expect(results.count { |attributes| attributes[:has_photos] }).to eq(5)
      expect(results.last[:has_photos]).to be(true)
      expect(results.size).to be > 5
    end

    it 'passa a posição de cada lugar ao filtro, de 1 em diante' do
      ranks = []
      provider.search { |_attributes, rank| ranks << rank }

      expect(ranks).to eq([1, 2, 3, 4, 5])
    end

    it 'não passa da posição máxima nem de 60' do
      expect(provider.search(max_results: 3) { |_attributes, _rank| false }.size).to eq(3)
      expect(provider.search(max_results: 500) { |_attributes, _rank| false }.size).to eq(60)
    end
  end
end
