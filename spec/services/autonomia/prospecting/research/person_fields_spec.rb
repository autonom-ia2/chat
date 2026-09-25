require 'rails_helper'

# Lista fechada de campos de pessoa física (#679). Tudo que for gravado sobre uma pessoa passa por aqui.
RSpec.describe Autonomia::Prospecting::Research::PersonFields do
  it 'é exatamente nome, qualificação e data de entrada' do
    expect(described_class::ALLOWED).to eq(%w[name qualification entered_on])
    expect(described_class::ALLOWED).to be_frozen
  end

  it 'devolve a entrada com chaves string quando só tem campos da lista' do
    entry = described_class.storable!(name: 'Ana', qualification: 'Sócio', entered_on: '2020-01-02')

    expect(entry).to eq('name' => 'Ana', 'qualification' => 'Sócio', 'entered_on' => '2020-01-02')
  end

  it 'levanta Violation na tentativa de gravar campo fora da lista, sem ecoar o valor' do
    expect { described_class.storable!('name' => 'Ana', 'cpf' => '***208478**', 'faixa_etaria' => '71 a 80 anos') }
      .to raise_error(described_class::Violation) { |error|
        expect(error.message).to include('cpf', 'faixa_etaria')
        expect(error.message).not_to include('208478')
      }
  end
end
