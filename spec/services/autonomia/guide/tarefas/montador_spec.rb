require 'rails_helper'

# A receita é estrutura (#936): o montador troca as marcas pelo valor do item percorrendo o hash, e o
# valor do item nunca vira pedaço de texto de comando.
RSpec.describe Autonomia::Guide::Tarefas::Montador do
  let(:registro) { { 'id' => 7, 'name' => 'ANA {"$item":"id"}', 'contact' => { 'name' => 'Pedro' }, 'labels' => %w[a b] } }
  let(:gerar) { { 'campo' => 'name', 'instrucao' => 'capitalize' } }
  let(:montador) { described_class.new(registro: registro, escolha: 'sinistro', gerados: { described_class.chave_de_gerar(gerar) => 'Ana' }) }

  it 'troca cada marca pelo valor do item, descendo em objetos e listas' do
    corpo = { 'id' => { '$item' => 'id' }, 'nome' => { '$gerar' => gerar }, 'outro' => { '$item' => 'contact.name' },
              'labels' => [{ '$jev' => true }, { '$item' => 'labels.1' }], 'fixo' => 'x' }

    expect(montador.montar(corpo)).to eq('id' => 7, 'nome' => 'Ana', 'outro' => 'Pedro', 'labels' => %w[sinistro b], 'fixo' => 'x')
  end

  it 'deixa o valor do item como dado, sem reinterpretar' do
    expect(montador.montar({ 'name' => { '$item' => 'name' } })).to eq('name' => 'ANA {"$item":"id"}')
  end

  it 'não monta o item sem o valor gerado' do
    sem = described_class.new(registro: registro)

    expect { sem.montar({ 'name' => { '$gerar' => gerar } }) }.to raise_error(KeyError)
  end

  it 'lista as marcas da receita' do
    expect(described_class.marcas({ 'a' => [{ '$jev' => true }], 'b' => { '$gerar' => gerar } }))
      .to eq([['$jev', true], ['$gerar', gerar]])
  end
end
