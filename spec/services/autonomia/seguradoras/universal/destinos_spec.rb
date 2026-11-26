require 'rails_helper'

RSpec.describe Autonomia::Seguradoras::Universal::Destinos do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:cliente) { Autonomia::Seguradoras::Universal::Cliente.new(login: 'corretor.teste', senha: 's3nha-teste') }

  around do |exemplo|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      exemplo.run
    ensure
      Rails.cache = original
    end
  end

  def stub_destinos
    stub_request(:get, "#{base}/v1/destinos").to_return(status: 200, body: file_fixture('../universal/destinos.json').read)
  end

  it 'devolve as siglas dos países em maiúsculas' do
    stub_destinos
    expect(described_class.siglas(cliente)).to eq(Set['BR', 'PT', 'ES'])
  end

  it 'a segunda chamada vem do cache' do
    stub = stub_destinos
    2.times { described_class.siglas(cliente) }
    expect(stub).to have_been_requested.once
  end

  it 'o cache é por emissor: outro login lê a sua própria lista, e a chave não leva o login' do
    stub = stub_destinos
    outro = Autonomia::Seguradoras::Universal::Cliente.new(login: 'outro.corretor.teste', senha: 's3nha-teste')
    allow(Rails.cache).to receive(:fetch).and_call_original

    [cliente, outro, cliente].each { |quem| described_class.siglas(quem) }

    expect(stub).to have_been_requested.twice
    expect(Rails.cache).not_to have_received(:fetch).with(a_string_including('corretor.teste'), anything)
  end

  it 'validas? aponta as siglas que a Universal não atende' do
    stub_destinos
    expect(described_class.validas?(%w[PT XX], cliente)).to eq([false, ['XX']])
  end

  it 'validas? aceita siglas atendidas' do
    stub_destinos
    expect(described_class.validas?(%w[BR], cliente)).to eq([true, []])
  end

  it 'nomes devolve o nome do país como a Universal escreve, na ordem pedida' do
    stub_destinos
    expect(described_class.nomes(%w[pt BR], cliente)).to eq(%w[Portugal Brasil])
  end

  it 'nomes fica com a sigla quando a Universal não conhece o país' do
    stub_destinos
    expect(described_class.nomes(%w[PT XX], cliente)).to eq(%w[Portugal XX])
  end

  it 'nomes com a API fora fica com as siglas e a falha não fica no cache' do
    stub_request(:get, "#{base}/v1/destinos").to_timeout
    expect(described_class.nomes(%w[pt ES], cliente)).to eq(%w[PT ES])
    stub_destinos
    expect(described_class.nomes(%w[ES], cliente)).to eq(['Espanha'])
  end

  it 'paises lido uma vez serve para conferir e para nomear, sem nova chamada' do
    stub = stub_request(:get, "#{base}/v1/destinos").to_timeout
    mapa = described_class.paises(cliente)
    expect(described_class.validas_em?(%w[PT], mapa)).to eq([true, []])
    expect(described_class.nomes_em(%w[pt], mapa)).to eq(['PT'])
    expect(stub).to have_been_requested.once
    stub_destinos
    mapa = described_class.paises(cliente)
    expect(described_class.validas_em?(%w[PT XX], mapa)).to eq([false, ['XX']])
    expect(described_class.nomes_em(%w[pt], mapa)).to eq(['Portugal'])
  end

  it 'lista vazia conta como falha e não fica no cache' do
    stub_request(:get, "#{base}/v1/destinos").to_return(status: 200, body: '[]')
    expect(described_class.siglas(cliente)).to be_nil
    expect(described_class.validas?(%w[PT], cliente)).to eq([true, []])
    stub_destinos
    expect(described_class.siglas(cliente)).to eq(Set['BR', 'PT', 'ES'])
  end

  it 'API fora: siglas nil, validas? não barra e a falha não fica no cache' do
    stub_request(:get, "#{base}/v1/destinos").to_timeout
    expect(described_class.siglas(cliente)).to be_nil
    expect(described_class.validas?(%w[PT], cliente)).to eq([true, []])
    stub_destinos
    expect(described_class.siglas(cliente)).to eq(Set['BR', 'PT', 'ES'])
  end
end
