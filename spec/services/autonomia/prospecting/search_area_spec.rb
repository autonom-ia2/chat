require 'rails_helper'

# Área desenhada da busca (#678, E2 frente B): círculo, retângulo e polígono.
RSpec.describe Autonomia::Prospecting::SearchArea do
  # Um "U" em Curitiba: o vão do meio fica dentro do retângulo que contém o polígono, mas fora dele.
  let(:u_path) do
    [
      { 'lat' => -25.50, 'lng' => -49.30 }, { 'lat' => -25.50, 'lng' => -49.20 },
      { 'lat' => -25.40, 'lng' => -49.20 }, { 'lat' => -25.40, 'lng' => -49.23 },
      { 'lat' => -25.45, 'lng' => -49.23 }, { 'lat' => -25.45, 'lng' => -49.27 },
      { 'lat' => -25.40, 'lng' => -49.27 }, { 'lat' => -25.40, 'lng' => -49.30 }
    ]
  end

  describe '.normalize' do
    it 'guarda centro e raio do círculo desenhado' do
      config = described_class.normalize('circle', { 'center' => { 'lat' => '-25.4284', 'lng' => -49.2733 } }, radius: 3200)

      expect(config).to eq('center' => { 'lat' => -25.4284, 'lng' => -49.2733 }, 'radius' => 3200)
    end

    it 'guarda os limites do retângulo em ordem e o centro dele' do
      config = described_class.normalize(
        'rectangle', { 'bounds' => { 'north' => -25.5, 'south' => -25.4, 'east' => -49.2, 'west' => -49.3 } }, radius: 1000
      )

      expect(config).to eq(
        'bounds' => { 'north' => -25.4, 'south' => -25.5, 'east' => -49.2, 'west' => -49.3 },
        'center' => { 'lat' => -25.45, 'lng' => -49.25 }
      )
    end

    it 'guarda os pontos do polígono, o retângulo que o contém e o centro' do
      config = described_class.normalize('polygon', { 'path' => u_path }, radius: 1000)

      expect(config['path'].size).to eq(8)
      expect(config['bounds']).to eq('north' => -25.4, 'south' => -25.5, 'east' => -49.2, 'west' => -49.3)
      expect(config['center']).to eq('lat' => -25.45, 'lng' => -49.25)
    end

    it 'recusa polígono com menos de três pontos válidos' do
      path = [{ 'lat' => -25.5, 'lng' => -49.3 }, { 'lat' => -25.4, 'lng' => 'x' }, { 'lat' => -25.4, 'lng' => -49.2 }]

      expect(described_class.normalize('polygon', { 'path' => path }, radius: 1000)).to be_nil
    end

    it 'recusa polígono com pontos demais' do
      path = Array.new(described_class::MAX_POLYGON_POINTS + 1) { |index| { 'lat' => -25.0 - (index * 0.001), 'lng' => -49.0 } }

      expect(described_class.normalize('polygon', { 'path' => path }, radius: 1000)).to be_nil
    end

    it 'recusa círculo sem centro e retângulo sem os quatro limites' do
      expect(described_class.normalize('circle', {}, radius: 1000)).to be_nil
      expect(described_class.normalize('rectangle', { 'bounds' => { 'north' => 1, 'south' => 0 } }, radius: 1000)).to be_nil
    end
  end

  describe '.contains?' do
    let(:config) { described_class.normalize('polygon', { 'path' => u_path }, radius: 1000) }

    it 'aceita ponto dentro de um braço do polígono côncavo' do
      expect(described_class.contains?('polygon', config, -25.42, -49.29)).to be(true)
      expect(described_class.contains?('polygon', config, -25.48, -49.25)).to be(true)
    end

    it 'descarta ponto no vão: dentro do retângulo, fora do polígono' do
      expect(described_class.contains?('polygon', config, -25.42, -49.25)).to be(false)
    end

    it 'descarta ponto fora do retângulo e lugar sem coordenada' do
      expect(described_class.contains?('polygon', config, -25.30, -49.25)).to be(false)
      expect(described_class.contains?('polygon', config, nil, -49.25)).to be(false)
    end

    it 'não recorta círculo, retângulo, raio nem área visível' do
      %w[circle rectangle radius viewport].each do |area_type|
        expect(described_class.contains?(area_type, {}, nil, nil)).to be(true)
      end
    end
  end

  describe '.google_location' do
    it 'círculo vai como locationBias circle, com o raio limitado a 50 km' do
      config = { 'center' => { 'lat' => -25.43, 'lng' => -49.27 }, 'radius' => 80_000 }

      expect(described_class.google_location('circle', config, radius: 80_000)).to eq(
        locationBias: { circle: { center: { latitude: -25.43, longitude: -49.27 }, radius: 50_000 } }
      )
    end

    it 'retângulo vai como locationRestriction rectangle' do
      config = { 'bounds' => { 'north' => -25.4, 'south' => -25.5, 'east' => -49.2, 'west' => -49.3 } }

      expect(described_class.google_location('rectangle', config, radius: 1000)).to eq(
        locationRestriction: {
          rectangle: { low: { latitude: -25.5, longitude: -49.3 }, high: { latitude: -25.4, longitude: -49.2 } }
        }
      )
    end

    it 'polígono pede o retângulo que o contém como locationRestriction' do
      config = described_class.normalize('polygon', { 'path' => u_path }, radius: 1000)

      expect(described_class.google_location('polygon', config, radius: 1000)).to eq(
        locationRestriction: {
          rectangle: { low: { latitude: -25.5, longitude: -49.3 }, high: { latitude: -25.4, longitude: -49.2 } }
        }
      )
    end

    it 'área visível continua como locationBias rectangle e raio como locationBias circle' do
      viewport = { 'bounds' => { 'north' => -25.4, 'south' => -25.5, 'east' => -49.2, 'west' => -49.3 } }
      radius = { 'center' => { 'lat' => -25.43, 'lng' => -49.27 } }

      expect(described_class.google_location('viewport', viewport, radius: 1000).keys).to eq([:locationBias])
      expect(described_class.google_location('viewport', viewport, radius: 1000)[:locationBias]).to have_key(:rectangle)
      expect(described_class.google_location('radius', radius, radius: 2000)).to eq(
        locationBias: { circle: { center: { latitude: -25.43, longitude: -49.27 }, radius: 2000 } }
      )
      expect(described_class.google_location('radius', {}, radius: 2000)).to eq({})
    end
  end
end
