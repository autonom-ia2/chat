require 'rails_helper'

RSpec.describe Autonomia::Agents::Knowledge::Ingestor do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente Teste', agent_type: 'support')
  end
  let(:source) do
    Autonomia::Agents::Source.create!(account: account, agent: agent, source_type: 'pdf', status: :pending)
  end
  let(:processor) { instance_double(Autonomia::Agents::Knowledge::Processors::Pdf) }
  let(:embedder) { instance_double(Autonomia::Agents::EmbeddingService) }
  let(:classifier) { instance_double(Autonomia::Agents::Knowledge::DocumentClassifier) }

  # Documento de prosa com um cabeçalho gritado + corpo — gera >= 1 chunk com heading herdado.
  let(:text) do
    "POLITICA DE REEMBOLSO\n\nO reembolso integral e processado em ate trinta dias uteis para o cliente."
  end
  let(:doc_classification) do
    { topics: ['Reembolso'], entities: ['Plano Plus'], doc_style: 'formal' }
  end
  # Vetor fake com a dimensão da coluna ativa (1536) — extraído p/ constante local (Performance).
  let(:fake_vector) { Array.new(1536, 0.1) }

  def run!
    token = source.begin_ingestion!
    described_class.new(source: source, token: token).perform
  end

  before do
    # O Ingestor chama Processors::Dispatcher.for (método de classe verificável); stubamos o
    # dispatcher p/ não tocar o extrator real de PDF.
    allow(Autonomia::Agents::Knowledge::Processors::Dispatcher).to receive(:for).with(source).and_return(processor)
    allow(processor).to receive(:extract).and_return(text)
    # 1 vetor por chunk (qualquer chunk count); vetor não-vazio p/ passar do guard de embeddings.
    allow(embedder).to receive(:embed_batch) { |chunks| chunks.map { fake_vector } }
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)
    allow(Autonomia::Agents::Knowledge::DocumentClassifier).to receive(:new).and_return(classifier)
    allow(classifier).to receive(:classify).and_return(doc_classification)
  end

  describe '#perform' do
    it 'calls the DocumentClassifier exactly once for the source' do
      # Assert
      expect(Autonomia::Agents::Knowledge::DocumentClassifier).to receive(:new)
        .with(source: source, text: text).once.and_return(classifier)
      expect(classifier).to receive(:classify).once.and_return(doc_classification)

      # Act
      run!
    end

    it 'stamps deterministic per-chunk metadata (source_type + heading + material_type + keywords)' do
      # Act
      run!

      # Assert
      meta = source.reload.knowledge_entries.order(:chunk_index).first.metadata
      expect(meta).to include(
        'source_type' => 'pdf', 'section_heading' => 'POLITICA DE REEMBOLSO', 'material_type' => 'prose'
      )
      expect(meta['keywords']).to include('reembolso')
    end

    it 'stamps the document classification (doc.topics/entities/style) on the chunk metadata' do
      # Act
      run!

      # Assert
      doc = source.reload.knowledge_entries.order(:chunk_index).first.metadata['doc']
      expect(doc).to eq('topics' => ['Reembolso'], 'entities' => ['Plano Plus'], 'style' => 'formal')
    end

    it 'embeds the chunk TEXT (heading-inherited), one vector per chunk' do
      # Assert — o embedder recebe strings, não hashes; e o texto carrega o cabeçalho herdado.
      expect(embedder).to receive(:embed_batch) do |chunks|
        expect(chunks).to all(be_a(String))
        expect(chunks.first).to start_with('POLITICA DE REEMBOLSO')
        chunks.map { fake_vector }
      end

      # Act
      run!
    end

    it 'raises EmptyExtraction and writes nothing when extraction is empty' do
      # Arrange
      allow(processor).to receive(:extract).and_return('   ')

      # Act / Assert
      expect { run! }.to raise_error(described_class::EmptyExtraction)
      expect(source.reload.knowledge_entries.count).to eq(0)
    end

    it 'still ingests when the classifier degrades to empty (best-effort)' do
      # Arrange — classificação vazia (IA indisponível): metadata.doc fica com listas vazias, mas os
      # entries são gravados normalmente (a classificação nunca bloqueia a ingestão).
      allow(classifier).to receive(:classify).and_return(topics: [], entities: [], doc_style: nil)

      # Act
      count = run!

      # Assert
      expect(count).to be >= 1
      meta = source.reload.knowledge_entries.first.metadata
      expect(meta.dig('doc', 'topics')).to eq([])
      expect(meta.dig('doc', 'style')).to be_nil
    end
  end

  # #1426 (t4e) — PDF grande dividido em seções pelo processador: cada trecho guarda as páginas da seção de onde veio.
  describe '#perform with the sections of a large PDF' do
    let(:secoes) do
      [{ 'paginas' => [1, 25], 'texto' => "COBERTURAS\n\nA cobertura basica protege o veiculo contra colisao e incendio." },
       { 'paginas' => [201, 225], 'texto' => "ASSISTENCIA 24 HORAS\n\nO guincho atende ate duzentos quilometros da residencia." }]
    end

    before do
      allow(processor).to receive(:extract) do
        source.secoes = secoes
        secoes.pluck('texto').join("\n\n")
      end
    end

    it 'stamps the pages of its section on every chunk' do
      run!

      entries = source.reload.knowledge_entries.order(:chunk_index)
      guincho = entries.find { |entry| entry.content.include?('guincho') }
      expect(guincho.metadata['paginas']).to eq([201, 225])
      expect(entries.first.metadata['paginas']).to eq([1, 25])
    end

    it 'keeps the chunk index continuous across the sections' do
      run!

      expect(source.reload.knowledge_entries.order(:chunk_index).pluck(:chunk_index)).to eq((0...source.knowledge_entries.count).to_a)
    end
  end

  # #1431 (F1) — o processor entregou blocos (flag rag_corte_por_estrutura): o corte é por seção, e não pelo Chunker.
  describe '#perform with the blocks the processor read' do
    let(:blocos) do
      [{ tipo: :titulo, nivel: 1, texto: 'COBERTURAS', pagina: 3 },
       { tipo: :paragrafo, texto: 'A cobertura basica protege o veiculo contra colisao, incendio e roubo total. ' * 4, pagina: 3 },
       { tipo: :titulo, nivel: 1, texto: 'ASSISTENCIA 24 HORAS', pagina: 9 },
       { tipo: :paragrafo, texto: 'O guincho atende ate duzentos quilometros da residencia do segurado. ' * 4, pagina: 9 }]
    end

    before do
      allow(processor).to receive(:extract) do
        source.blocos = blocos
        blocos.pluck(:texto).join("\n\n")
      end
    end

    it 'cuts by section, with the path and the pages on every piece', :aggregate_failures do
      source.update!(reference: 'condicoes-gerais.pdf')
      run!

      guincho = source.reload.knowledge_entries.order(:chunk_index).last
      expect(guincho.content).to start_with("ASSISTENCIA 24 HORAS\n\n")
      expect(guincho.metadata).to include('paginas_do_trecho' => [9, 9], 'section_heading' => 'ASSISTENCIA 24 HORAS',
                                          'material_type' => 'secao')
      expect(guincho.metadata['caminho']).to eq(['condicoes-gerais', 'ASSISTENCIA 24 HORAS'])
      expect(guincho.metadata['secao_id']).to be_present
    end

    # PR 1b: o trecho de item aponta para o chunk_index do trecho da seção; o vetor vazio no meio não pode deslocá-lo, e o
    # "N trechos" do material não conta item.
    context 'with item pieces' do
      let(:fileiras) { (1..4).map { |n| "Prazo: #{n * 15} dias | % do premio: #{n * 10}%" } }
      let(:blocos) do
        [{ tipo: :titulo, nivel: 1, texto: 'COBERTURAS', pagina: 3 },
         { tipo: :paragrafo, texto: 'A cobertura basica protege o veiculo contra colisao, incendio e roubo total. ' * 4, pagina: 3 },
         { tipo: :titulo, nivel: 1, texto: 'PRAZO CURTO', pagina: 9 },
         { tipo: :tabela, texto: fileiras.join("\n"), itens: fileiras, pagina: 9 }]
      end

      it 'keeps the pointer of every item on its section piece, even after an empty vector', :aggregate_failures do
        allow(embedder).to receive(:embed_batch) { |chunks| chunks.each_with_index.map { |_, indice| indice.zero? ? [] : fake_vector } }

        count = run!
        entries = source.reload.knowledge_entries.order(:chunk_index).to_a
        itens = entries.select { |entry| entry.metadata['material_type'] == 'item' }

        expect(itens.size).to eq(4)
        pai = ->(item) { entries.find { |e| e.chunk_index == item.metadata['trecho_da_secao'] } }
        expect(itens).to all(satisfy { |item| pai.call(item)&.content&.include?(item.content.split("\n\n", 2).last) })
        expect(count).to eq(1)
      end
    end

    # A chave `paginas` é a seção de 25 páginas do material grande: o ResumoPorSecao agrupa por ela (chamada paga por
    # seção) e o Revisor reconhece o material grande por ela. PDF pequeno não a recebe só por ter sido cortado por seção.
    it 'gives a small PDF no `paginas`, so the summary by section and the Reviewer see a small material' do
      run!

      expect(source.reload.knowledge_entries.where("metadata ? 'paginas'")).to be_empty
    end

    it 'stamps the 25-page section where each piece starts on a large PDF', :aggregate_failures do
      allow(processor).to receive(:extract) do
        source.blocos = blocos
        source.secoes = [{ 'paginas' => [1, 5], 'texto' => 'COBERTURAS' }, { 'paginas' => [6, 10], 'texto' => 'ASSISTENCIA' }]
        blocos.pluck(:texto).join("\n\n")
      end
      run!

      entries = source.reload.knowledge_entries.order(:chunk_index)
      expect(entries.first.metadata).to include('paginas' => [1, 5], 'paginas_do_trecho' => [3, 3])
      expect(entries.last.metadata).to include('paginas' => [6, 10], 'paginas_do_trecho' => [9, 9])
    end

    it 'leaves the document name out of the path when the material has none' do
      source.update!(reference: nil)
      run!

      expect(source.reload.knowledge_entries.order(:chunk_index).last.content).to start_with("ASSISTENCIA 24 HORAS\n\n")
    end
  end

  it 'leaves the pages out of the metadata when the material has no sections' do
    run!

    expect(source.reload.knowledge_entries.first.metadata).not_to have_key('paginas')
  end

  # B1 — com o modelo 3-large ativo, o Ingestor grava na coluna halfvec `embedding_large` (SQL cru) e
  # deixa a coluna legada `embedding` (vector 1536) NULL — a base fica pronta p/ o cutover sem misturar.
  describe '#perform with the large embedding model active' do
    before do
      allow(Autonomia::Agents::Config).to receive(:active_embedding_model).and_return('text-embedding-3-large')
      allow(embedder).to receive(:embed_batch) { |chunks| chunks.map { Array.new(3072, 0.01) } }
    end

    it 'writes to embedding_large (halfvec) and leaves the legacy embedding NULL' do
      # Act
      run!

      # Assert
      entry = source.reload.knowledge_entries.order(:chunk_index).first
      expect(entry.read_attribute(:embedding)).to be_nil
      populated = Autonomia::Agents::KnowledgeEntry.where(id: entry.id).where.not(embedding_large: nil).count
      expect(populated).to eq(1)
    end
  end
end
