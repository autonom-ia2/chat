require 'rails_helper'

RSpec.describe Autonomia::Prospecting::SearchCountry do
  it 'oferece os 19 países do Orth, com o Brasil como padrão' do
    expect(described_class::ALLOWED).to eq(%w[BR PT US FR ES DE IT GB MX AR CL CO PE EC PY UY AT IE IN])
    expect(described_class::DEFAULT).to eq('BR')
  end

  describe '.normalize' do
    it 'aceita o código em minúsculas e com espaço' do
      expect(described_class.normalize(' pt ')).to eq('PT')
    end

    it 'devolve nil para país fora da lista ou vazio' do
      expect(described_class.normalize('ZZ')).to be_nil
      expect(described_class.normalize('')).to be_nil
      expect(described_class.normalize(nil)).to be_nil
    end
  end

  describe '.language_code' do
    it 'segue o mapa país-idioma do Orth' do
      expect(%w[BR PT US MX DE].map { |country| described_class.language_code(country) }).to eq(%w[pt-BR pt-PT en es de])
    end
  end
end
