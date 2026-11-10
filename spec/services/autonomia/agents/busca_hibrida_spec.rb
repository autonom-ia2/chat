require 'rails_helper'

# #2867 (Refs #1431 #2810) — a ordem da busca híbrida. Com peso igual nas duas listas, todo trecho que estava nas duas
# (mesmo no 48º lugar de cada: 2/108) passava na frente do 1º do vetor que não casava a palavra (1/61), e o trecho
# certo caía para o 5º–11º lugar. Agora o 1º do vetor fica na frente, e a palavra pesa menos que o vetor: sobe o trecho
# que casa a palavra e está perto no sentido, não o que só repete palavras comuns.
RSpec.describe Autonomia::Agents::BuscaHibrida do
  let(:trecho) { Struct.new(:id, :neighbor_distance) }
  let(:busca) do
    described_class.new(escopo: Autonomia::Agents::KnowledgeEntry.none, vector: [0.1], model: 'text-embedding-3-small',
                        query: 'pergunta')
  end

  # ids 1..n, na ordem do vetor, todos dentro do teto
  def vetor(quantidade)
    (1..quantidade).map { |id| trecho.new(id, 0.3 + (id / 1000.0)) }
  end

  def fundir(vetoriais, da_palavra)
    allow(busca).to receive(:por_palavra).and_return(da_palavra)
    busca.fundir(vetoriais, 48).map(&:id)
  end

  it 'keeps the first of the vector in front even when every other piece also matches the words' do
    vetoriais = vetor(48)

    expect(fundir(vetoriais, vetoriais.drop(1).reverse).first).to eq(1)
  end

  it 'raises a word hit that is near in the vector above the vector hits around it' do
    vetoriais = vetor(10)

    expect(fundir(vetoriais, [vetoriais[4]]).first(3)).to eq([1, 5, 2])
  end

  it 'keeps a word hit that is far in the vector below the near vector hits' do
    vetoriais = vetor(40)

    expect(fundir(vetoriais, [vetoriais[29]]).first(6)).to eq([1, 2, 3, 4, 5, 30])
  end

  it 'puts a piece found only by the words after the vector ones' do
    so_da_palavra = trecho.new(99, 0.5)

    expect(fundir(vetor(3), [so_da_palavra])).to eq([1, 2, 3, 99])
  end

  it 'puts nothing in front when the first of the vector is beyond the distance ceiling' do
    longe = trecho.new(1, Autonomia::Agents::Config::RETRIEVAL_HARD_CEILING + 0.1)

    expect(fundir([longe], [])).to eq([])
  end
end
