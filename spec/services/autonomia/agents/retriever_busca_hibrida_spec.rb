require 'rails_helper'

# #2810 (Refs #1431) — busca híbrida. Com a flag `rag_busca_hibrida`, os candidatos do vetor e os da busca por palavra
# (texto em português, com ranking) entram juntos e a ordem sai da fusão por posição (RRF, k = 60), no lugar do bônus
# por metadado. O trecho que repete as palavras da pergunta sobe mesmo quando o vetor o deixou atrás. O teto de
# distância, as seções dos itens, o material reprovado e o isolamento por agente continuam valendo.
RSpec.describe Autonomia::Agents::Retriever do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
  let(:embedding_service) { instance_double(Autonomia::Agents::EmbeddingService) }
  let(:perto) { Array.new(1536) { 0.01 } }
  # cosseno 664/1536 com `perto`: distância ~0,57, dentro do teto de 0,75
  let(:meio) { Array.new(1536) { |indice| indice < 1100 ? 0.01 : -0.01 } }
  # cosseno 0 com `perto`: distância 1,0, acima do teto
  let(:longe) { Array.new(1536) { |indice| indice.even? ? 0.01 : -0.01 } }
  let(:source) { agent.sources.create!(account: account, source_type: 'pdf', status: :ready, reference: 'cg.pdf') }
  let(:pergunta) { 'Bati o carro, qual o telefone para o aviso de sinistro?' }

  # opcoes: metadata:, fonte: (o material) e alvo: (o agente), quando não são os de sempre.
  def entry(indice, content, embedding, **opcoes)
    alvo = opcoes.fetch(:alvo, agent)
    alvo.knowledge_entries.create!(account: alvo.account, source: opcoes.fetch(:fonte, source), content: content,
                                   status: :ready, chunk_index: indice, metadata: opcoes.fetch(:metadata, {}),
                                   embedding: embedding)
  end

  def buscar(top_k: Autonomia::Agents::Config::RETRIEVER_TOP_K)
    described_class.new(agent: agent.reload).retrieve(pergunta, top_k: top_k)
  end

  before do
    allow(embedding_service).to receive(:embed).and_return(perto)
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedding_service)
  end

  context 'with the flag on' do
    before { account.enable_features!('rag_busca_hibrida') }

    it 'puts first the piece that repeats the words of the question, even behind in the vector' do
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      aviso = entry(1, 'Aviso de sinistro: comunique a seguradora pelo telefone 0800 000 0000.', meio)

      expect(buscar.map(&:id).first).to eq(aviso.id)
    end

    # top_k 2: o vetor traz 8 candidatos, todos os 9 trechos perto; o aviso só chega pela busca por palavra.
    it 'brings a piece the vector left out of its candidates, with its real distance', :aggregate_failures do
      9.times { |indice| entry(indice, "Assistência #{indice}: reboque e chaveiro.", perto) }
      aviso = entry(20, 'Aviso de sinistro: comunique a seguradora pelo telefone 0800 000 0000.', meio)

      resultado = buscar(top_k: 2)

      expect(resultado.map(&:id)).to include(aviso.id)
      expect(resultado.find { |trecho| trecho.id == aviso.id }.neighbor_distance.to_f).to be_between(0.5, 0.65)
    end

    # Os trechos longe que repetem mais as palavras não podem ocupar as vagas da busca por palavra: o teto vem antes do
    # limite.
    it 'applies the distance ceiling before the limit of the word search' do
      9.times { |indice| entry(indice, "Assistência #{indice}: reboque e chaveiro.", perto) }
      9.times { |indice| entry(30 + indice, 'Aviso de sinistro: telefone do aviso de sinistro, telefone, aviso, carro.', longe) }
      aviso = entry(20, 'Aviso de sinistro: comunique a seguradora pelo telefone 0800 000 0000.', meio)

      expect(buscar(top_k: 2).map(&:id)).to include(aviso.id)
    end

    # O OU entre os termos não pode mexer dentro de um termo: o `&` de um endereço faz parte da palavra.
    it 'matches a link with & in it as the same word' do
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      boleto = entry(1, 'Segunda via em https://outro.com/2via?cpf=1&tipo=2', meio)

      resultado = described_class.new(agent: agent.reload).retrieve('https://pagar.com/2via?cpf=1&tipo=2')

      expect(resultado.map(&:id).first).to eq(boleto.id)
    end

    # O Guia e o Ajudante passam texto que não foi gravado antes; o Postgres não aceita o byte nulo num literal.
    it 'searches a question with a null byte like the same question without it' do
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      aviso = entry(1, 'Aviso de sinistro: comunique a seguradora pelo telefone 0800 000 0000.', meio)

      resultado = described_class.new(agent: agent.reload).retrieve("aviso de sinistro\u0000telefone")

      expect(resultado.map(&:id).first).to eq(aviso.id)
    end

    # Cliente que cola a apólice: termos repetidos entram uma vez só no OU.
    it 'answers a long question that repeats its words without slowing down' do
      entry(0, 'Aviso de sinistro: comunique a seguradora pelo telefone 0800 000 0000.', meio)

      tempo = Benchmark.realtime { described_class.new(agent: agent.reload).retrieve('aviso de sinistro telefone ' * 300) }

      expect(tempo).to be < 2
    end

    it 'answers with the vector alone when the question has no searchable word' do
      reboque = entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)

      expect(described_class.new(agent: agent.reload).retrieve('?! ...').map(&:id)).to eq([reboque.id])
    end

    it 'leaves out a piece with no embedding, even when it matches the words' do
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      sem_vetor = entry(1, 'Aviso de sinistro: telefone 0800 000 0000.', nil)

      expect(buscar.map(&:id)).not_to include(sem_vetor.id)
    end

    it 'keeps out a piece that matches the words but is beyond the distance ceiling' do
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      fora = entry(1, 'Aviso de sinistro: telefone 0800 000 0000.', longe)

      expect(buscar.map(&:id)).not_to include(fora.id)
    end

    it 'still gives back the section in place of the item' do
      secao = entry(0, "Aviso de sinistro\n\na) comunique pelo telefone 0800;\nb) registre o boletim;", longe,
                    metadata: { 'material_type' => 'secao' })
      entry(1, "Aviso de sinistro\n\na) comunique pelo telefone 0800;", meio, metadata: { 'material_type' => 'item', 'trecho_da_secao' => 0 })

      expect(buscar.map(&:id)).to eq([secao.id])
    end

    it 'keeps the material sent back by the review out of the word search' do
      reprovada = agent.sources.create!(account: account, source_type: 'txt', status: :ready, review_status: 'needs_resend',
                                        reference: 'reprovado.txt')
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      fora = entry(0, 'Aviso de sinistro: telefone 0800 000 0000.', meio, fonte: reprovada)

      expect(buscar.map(&:id)).not_to include(fora.id)
    end

    it 'never brings a piece of another agent' do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'custom', status: :active,
                                               enabled: true, instruction: 'Outro.')
      fonte = outro.sources.create!(account: account, source_type: 'pdf', status: :ready, reference: 'outro.pdf')
      entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      alheio = entry(0, 'Aviso de sinistro: telefone 0800 000 0000.', perto, fonte: fonte, alvo: outro)

      expect(buscar.map(&:id)).not_to include(alheio.id)
    end
  end

  context 'with the flag on and the large model (halfvec)' do
    let(:grande) { Array.new(3072) { 0.01 } }

    before do
      account.enable_features!('rag_busca_hibrida')
      allow(Autonomia::Agents::Config).to receive(:embedding_large?).and_return(true)
      allow(embedding_service).to receive(:embed).and_return(grande)
    end

    def entry_grande(indice, content, vetor)
      trecho = agent.knowledge_entries.create!(account: account, source: source, content: content, status: :ready,
                                               chunk_index: indice, metadata: {})
      # update_all: escrita direta do halfvec de teste (mesmo caminho do Ingestor).
      agent.knowledge_entries.where(id: trecho.id)
           .update_all(['embedding_large = ?::halfvec', "[#{vetor.join(',')}]"]) # rubocop:disable Rails/SkipsModelValidations
      trecho
    end

    it 'measures the word hits on the large column and skips rows not yet backfilled', :aggregate_failures do
      aviso = entry_grande(0, 'Aviso de sinistro: telefone 0800 000 0000.', grande)
      pendente = agent.knowledge_entries.create!(account: account, source: source, content: 'Aviso de sinistro: telefone.',
                                                 status: :ready, chunk_index: 1, metadata: {})

      resultado = buscar

      expect(resultado.map(&:id)).to eq([aviso.id])
      expect(resultado.first.neighbor_distance.to_f).to be < 0.01
      expect(resultado.map(&:id)).not_to include(pendente.id)
    end
  end

  context 'with the flag off' do
    it 'keeps the vector order of today' do
      reboque = entry(0, 'Reboque e chaveiro em todo o Brasil.', perto)
      entry(1, 'Aviso de sinistro: comunique a seguradora pelo telefone 0800 000 0000.', meio)

      expect(buscar.map(&:id).first).to eq(reboque.id)
    end
  end
end
