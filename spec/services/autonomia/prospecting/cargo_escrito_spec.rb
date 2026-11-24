require 'rails_helper'

RSpec.describe Autonomia::Prospecting::CargoEscrito do
  let(:marca) { described_class::WRITTEN_KEY }

  # MOTIVO: campo vazio recebe o cargo do decisor, com a marca de que fomos nós.
  it 'grava o cargo e a marca no campo vazio' do
    expect(described_class.new('cor_favorita' => 'azul').com('SOCIA')).to eq('cor_favorita' => 'azul', 'job_title' => 'SOCIA', marca => 'SOCIA')
  end

  # MOTIVO: o cargo que nós gravamos (igual à marca) é trocado; sem decisor, sai junto com a marca.
  it 'troca e tira só o cargo que nós gravamos', :aggregate_failures do
    nosso = { 'job_title' => 'SOCIA', marca => 'SOCIA' }

    expect(described_class.new(nosso).com('DIRETORA')).to eq('job_title' => 'DIRETORA', marca => 'DIRETORA')
    expect(described_class.new(nosso).com(nil)).to eq({})
  end

  # MOTIVO: o cargo que o usuário digitou (diferente da marca) nunca muda nem some.
  it 'não mexe no cargo que o usuário digitou', :aggregate_failures do
    do_usuario = { 'job_title' => 'Gerente', marca => 'SOCIA' }

    expect(described_class.new(do_usuario).com('DIRETORA')).to eq(do_usuario)
    expect(described_class.new(do_usuario).com(nil)).to eq(do_usuario)
  end

  # MOTIVO: o hash recebido não muda; quem chama grava o novo.
  it 'não altera o hash recebido' do
    recebido = { 'job_title' => nil }
    described_class.new(recebido).com('SOCIA')

    expect(recebido).to eq('job_title' => nil)
  end
end
