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

  it 'validas? aponta as siglas que a Universal não atende' do
    stub_destinos
    expect(described_class.validas?(%w[PT XX], cliente)).to eq([false, ['XX']])
  end

  it 'validas? aceita siglas atendidas' do
    stub_destinos
    expect(described_class.validas?(%w[BR], cliente)).to eq([true, []])
  end

  it 'API fora: siglas nil, validas? não barra e a falha não fica no cache' do
    stub_request(:get, "#{base}/v1/destinos").to_timeout
    expect(described_class.siglas(cliente)).to be_nil
    expect(described_class.validas?(%w[PT], cliente)).to eq([true, []])
    stub_destinos
    expect(described_class.siglas(cliente)).to eq(Set['BR', 'PT', 'ES'])
  end
end
