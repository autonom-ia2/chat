require 'rails_helper'

RSpec.describe Autonomia::Agents::PlacarDaBase do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:embedding_service) { instance_double(Autonomia::Agents::EmbeddingService) }
  # Cada pergunta é "embedada" num vetor escolhido aqui: a ordem da busca fica sob controle do teste.
  let(:vetores_das_perguntas) { {} }

  def vetor(pesos)
    Array.new(1536, 0.0).tap { |v| pesos.each { |indice, peso| v[indice] = peso } }
  end

  def pergunta(texto, ancoras: [], fora: false, eixo: 0)
    vetores_das_perguntas[texto] = vetor(eixo => 1.0)
    described_class::Pergunta.new(texto: texto, ancoras: ancoras, fora: fora)
  end

  before do
    allow(embedding_service).to receive(:embed) { |texto| vetores_das_perguntas.fetch(texto) }
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedding_service)
    # Distância de cosseno à pergunta do eixo 0: vidros 0, guincho 0,4. O eixo 2 fica longe dos dois (fora da base).
    agent.knowledge_entries.create!(account: account, content: 'Cobertura de VIDROS: para-brisa, vigias e retrovisores.',
                                    status: :ready, chunk_index: 0, metadata: {}, embedding: vetor(0 => 1.0))
    agent.knowledge_entries.create!(account: account, content: 'Assistência 24 horas com guincho até 200 km.',
                                    status: :ready, chunk_index: 1, metadata: {}, embedding: vetor(0 => 0.6, 1 => 0.8))
  end

  def medir(*perguntas)
    described_class.new(agent: agent, perguntas: perguntas).medir
  end

  it 'counts the position of the first passage that holds the anchor' do
    placar = medir(
      pergunta('cobre o vidro?', ancoras: ['para-brisa, vigias']),
      pergunta('tem reboque?', ancoras: ['guincho até 200 km'])
    )

    expect(placar[:hit]).to eq(1 => 0.5, 5 => 1.0, 12 => 1.0)
    expect(placar[:mrr]).to eq(0.75)
    expect(placar[:itens].map { |item| item[:posicao] }).to eq([1, 2])
  end

  it 'matches the anchor ignoring case, accents and spacing' do
    placar = medir(pergunta('cobre o vidro?', ancoras: ["cobertura   de vidros:\npara-brisa"]))

    expect(placar[:itens].first[:posicao]).to eq(1)

    placar = medir(pergunta('cobre o vidro?', ancoras: ['ASSISTENCIA 24   horas']))

    expect(placar[:itens].first[:posicao]).to eq(2)
  end

  it 'scores a miss when no retrieved passage holds any anchor' do
    placar = medir(pergunta('qual a franquia?', ancoras: ['franquia reduzida', 'franquia normal']))

    expect(placar[:hit]).to eq(1 => 0.0, 5 => 0.0, 12 => 0.0)
    expect(placar[:mrr]).to eq(0.0)
  end

  it 'keeps out-of-base questions apart from the hit rate and reports whether the search came back empty' do
    placar = medir(
      pergunta('cobre o vidro?', ancoras: ['para-brisa']),
      pergunta('vocês fazem seguro de vida?', fora: true, eixo: 2)
    )

    expect(placar).to include(perguntas: 2, respondiveis: 1, fora: 1)
    expect(placar[:hit][1]).to eq(1.0)
    expect(placar[:fora_sem_trecho]).to eq(1.0)
  end

  it 'reports the smallest distance per class so thresholds are calibrated from data' do
    placar = medir(
      pergunta('cobre o vidro?', ancoras: ['para-brisa']),
      pergunta('vocês fazem seguro de vida?', fora: true, eixo: 2)
    )

    expect(placar[:distancia][:respondiveis][:mediana]).to be_within(0.001).of(0.0)
    expect(placar[:distancia][:fora][:mediana]).to be_nil
    expect(placar[:itens].last).to include(fora: true, trechos: 0, menor_distancia: nil)
  end

  it 'keeps question text out of the summary' do
    placar = medir(pergunta('cobre o vidro?', ancoras: ['para-brisa']))
    resumo = described_class.resumo(placar)

    expect(resumo).not_to have_key(:itens)
    expect(resumo.to_json).not_to include('cobre o vidro')
    expect(resumo).to include(agente: agent.id, perguntas: 1)
  end

  it 'loads questions from a YAML file' do
    arquivo = Tempfile.new(['perguntas', '.yml'])
    arquivo.write({ 'perguntas' => [
      { 'pergunta' => 'cobre o vidro?', 'ancoras' => ['para-brisa'] },
      { 'pergunta' => 'seguro de vida?', 'fora' => true }
    ] }.to_yaml)
    arquivo.close

    perguntas = described_class.perguntas_do_arquivo(arquivo.path)

    expect(perguntas.map(&:texto)).to eq(['cobre o vidro?', 'seguro de vida?'])
    expect(perguntas.map(&:fora)).to eq([false, true])
    expect(perguntas.first.ancoras).to eq(['para-brisa'])
  ensure
    arquivo&.unlink
  end
end
