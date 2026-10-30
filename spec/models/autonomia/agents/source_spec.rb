require 'rails_helper'

RSpec.describe Autonomia::Agents::Source do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Agente Teste', agent_type: 'support')
  end
  let(:embedding_vector) { [1.0] + Array.new(1535, 0.0) }
  let(:source) do
    described_class.create!(
      account: account, agent: agent, source_type: 'txt', status: :ready,
      review_status: 'accepted', review_summary: 'Material bom e completo sobre o negócio.',
      review_label: 'otima', review_reason: 'Cobertura ampla.', quality_score: 9,
      confidence: 'alta', reviewed_at: 1.day.ago
    )
  end

  describe '#mark_failed! after a resync (G6)' do
    let!(:entry) do
      Autonomia::Agents::KnowledgeEntry.create!(
        account: account, agent: agent, source: source, chunk_index: 0, status: :ready,
        content: 'Horário de atendimento: segunda a sexta, das 9h às 18h.',
        embedding: embedding_vector
      )
    end

    def fail_resync_with_embedding_error
      token = source.begin_ingestion!
      ingestor = instance_double(Autonomia::Agents::Knowledge::Ingestor)
      allow(Autonomia::Agents::Knowledge::Ingestor).to receive(:new).and_return(ingestor)
      allow(ingestor).to receive(:perform)
        .and_raise(Autonomia::Agents::EmbeddingService::EmbeddingError, 'embedding_down')
      Autonomia::Agents::Knowledge::ProcessJob.perform_now(source.id, token)
    end

    it 'restores the previous accepted review when embedding fails during resync' do
      # Arrange
      expect(source).to be_accepted

      # Act
      fail_resync_with_embedding_error

      # Assert
      source.reload
      expect(source).to be_failed
      expect(source).to have_attributes(
        error: 'embedding_down', review_status: 'accepted', review_label: 'otima',
        review_summary: 'Material bom e completo sobre o negócio.',
        quality_score: 9, confidence: 'alta'
      )
      expect(source.reviewed_at).to be_present
    end

    it 'keeps the old chunks visible to the Retriever after a transient resync failure' do
      # Arrange
      fail_resync_with_embedding_error
      embedder = instance_double(Autonomia::Agents::EmbeddingService, embed: embedding_vector)
      allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)

      # Act
      results = Autonomia::Agents::Retriever.new(agent: agent).retrieve('horário de atendimento')

      # Assert
      expect(results.map(&:id)).to include(entry.id)
    end

    it 'does not promote a never-reviewed source when its first ingestion fails' do
      # Arrange
      fresh = described_class.create!(account: account, agent: agent, source_type: 'txt')
      token = fresh.begin_ingestion!

      # Act
      fresh.mark_failed!(token, 'boom')

      # Assert
      fresh.reload
      expect(fresh).to be_failed
      expect(fresh.review_status).to eq('needs_review')
    end
  end

  # #1426 — a foto da criação é material da base: tipo próprio, com anexo de imagem. Imagem continua recusada nos outros
  # tipos (um "pdf" que é foto não passa).
  describe 'foto' do
    def com_anexo(source_type, content_type)
      source = described_class.new(account: account, agent: agent, source_type: source_type, reference: 'x')
      source.file.attach(io: StringIO.new('bytes'), filename: 'x', content_type: content_type, identify: false)
      source
    end

    it 'accepts a photo as a foto source' do
      expect(com_anexo('foto', 'image/jpeg')).to be_valid
    end

    it 'refuses a photo in a source of another type' do
      expect(com_anexo('pdf', 'image/jpeg')).not_to be_valid
    end

    it 'refuses a document in a foto source' do
      expect(com_anexo('foto', 'application/pdf')).not_to be_valid
    end

    # A4 — a foto da criação divide a imagem com a conversa do Construtor: tirar da base não apaga a imagem.
    it 'keeps the image of the conversation when the photo of the creation leaves the base' do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'tabela.png', content_type: 'image/png',
                                                    identify: false)
      foto = described_class.create!(account: account, agent: agent, source_type: 'foto', reference: 'tabela.png',
                                     origem: described_class::ORIGEM_FOTO_DA_CRIACAO, file: blob)

      perform_enqueued_jobs { foto.destroy! }

      expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
    end

    it 'still removes the image of a photo that was sent straight to the base' do
      foto = com_anexo('foto', 'image/jpeg').tap(&:save!)
      blob_id = foto.file.blob.id

      perform_enqueued_jobs { foto.destroy! }

      expect(ActiveStorage::Blob.exists?(blob_id)).to be(false)
    end
  end

  # K5 — as páginas do PDF que ficaram de fora vão no mark_ready!, sob a guarda de token.
  describe '#mark_ready! with the pages left out' do
    let(:de_fora) { { 'ocr_teto' => 30, 'ocr_alem_do_teto' => 2 } }

    it 'records the pages left out with the current token' do
      token = source.begin_ingestion!
      source.paginas_de_fora = de_fora

      expect(source.mark_ready!(token, chunk_count: 3)).to be(true)
      expect(source.reload.metadata).to include('paginas_de_fora' => de_fora, 'chunk_count' => 3)
    end

    it 'does not write anything from a superseded job' do
      antigo = source.begin_ingestion!
      atual = described_class.find(source.id).begin_ingestion!
      source.paginas_de_fora = de_fora

      expect(source.mark_ready!(antigo, chunk_count: 3)).to be(false)
      expect(described_class.find(source.id)).to have_attributes(status: 'processing', sync_token: atual)
      expect(described_class.find(source.id).metadata).not_to have_key('paginas_de_fora')
    end

    it 'clears the mark when nothing was left out in the new reading' do
      source.update_columns(metadata: { 'paginas_de_fora' => de_fora }) # rubocop:disable Rails/SkipsModelValidations
      token = source.begin_ingestion!

      source.mark_ready!(token, chunk_count: 1)

      expect(source.reload.metadata).not_to have_key('paginas_de_fora')
    end

    # P2 — a releitura que volta vazia ou falha também troca a marca: sai a da leitura anterior, entra a desta.
    it 'replaces the mark of the previous reading when the reading fails or comes back empty' do
      source.update_columns(metadata: { 'paginas_de_fora' => de_fora }) # rubocop:disable Rails/SkipsModelValidations
      token = source.begin_ingestion!
      source.mark_failed!(token, 'empty_extraction')
      expect(source.reload.metadata).not_to have_key('paginas_de_fora')

      token = source.begin_ingestion!
      source.paginas_de_fora = { 'ocr_falhou' => [1, 2] }
      source.restore_previous_generation!(token)
      expect(source.reload.metadata['paginas_de_fora']).to eq('ocr_falhou' => [1, 2])
    end
  end

  # S6 — a leitura nova começa sem a marca da anterior.
  describe '#begin_ingestion! and the pages left out' do
    it 'drops the pages left out by the previous reading' do
      source.update_columns(metadata: { 'paginas_de_fora' => { 'ocr_falhou' => [1] }, 'chunk_count' => 3 }) # rubocop:disable Rails/SkipsModelValidations

      source.begin_ingestion!

      expect(source.reload.metadata).not_to have_key('paginas_de_fora')
      expect(source.metadata['chunk_count']).to eq(3)
    end
  end

  # Q1 — o OCR do PDF confere, antes de cada página, que esta leitura ainda é a vigente.
  describe '#leitura_vigente?' do
    it 'is true while this reading is the active one and false after another one wins' do
      source.begin_ingestion!
      expect(source.reload.leitura_vigente?).to be(true)

      described_class.find(source.id).begin_ingestion!
      expect(source.leitura_vigente?).to be(false)
    end
  end

  # R6 — releitura que volta vazia: a geração anterior volta como estava.
  describe '#restore_previous_generation!' do
    let(:antigo) { described_class.create!(account: account, agent: agent, source_type: 'txt', status: :ready) }

    context 'with the Fase 2 on' do
      before { Autonomia::Agents::Fase2.ligar!(account) }

      it 'brings an old material with no verdict back as ready, not reviewing forever' do
        token = antigo.begin_ingestion!
        expect(antigo.reload.metadata.dig('prev_review', 'legado')).to be(true)

        antigo.restore_previous_generation!(token)

        expect(antigo.reload).to have_attributes(status: 'ready', review_status: nil, reviewed_at: nil)
      end

      # K1 — a corrida da sonda: material novo (nunca revisado), duas leituras seguidas e a segunda volta vazia. Sem
      # parecer também, mas não é legado: volta needs_review, fora da busca, e nunca é servido sem revisão.
      it 'keeps a new, never reviewed material out of the search after a race of two readings' do
        novo = described_class.create!(account: account, agent: agent, source_type: 'txt', reference: 'a.txt')
        novo.begin_ingestion!
        token_b = novo.reload.begin_ingestion!

        novo.reload.restore_previous_generation!(token_b)

        expect(novo.reload).to have_attributes(status: 'ready', review_status: 'needs_review')
        expect(novo.metadata['prev_review']).not_to have_key('legado')
      end

      it 'does not mark as old a material that already has a review date' do
        revisado = described_class.create!(account: account, agent: agent, source_type: 'txt', status: :ready, reviewed_at: 1.day.ago)
        token = revisado.begin_ingestion!

        revisado.restore_previous_generation!(token)

        expect(revisado.reload.review_status).to eq('needs_review')
      end
    end

    # Q5 — mídia de envio (sem parecer, pronta) nunca é legado.
    it 'never marks a media to send as old, even in the Fase 2' do
      Autonomia::Agents::Fase2.ligar!(account)
      midia = described_class.create!(account: account, agent: agent, source_type: 'txt', status: :ready, kind: :media)

      midia.begin_ingestion!

      expect(midia.reload.metadata['prev_review']).not_to have_key('legado')
    end

    # Fora da Fase 2, idêntico à main: sem parecer anterior volta needs_review.
    it 'brings an old material with no verdict back as needs_review outside the Fase 2' do
      token = antigo.begin_ingestion!
      expect(antigo.reload.metadata['prev_review']).not_to have_key('legado')

      antigo.restore_previous_generation!(token)

      expect(antigo.reload).to have_attributes(status: 'ready', review_status: 'needs_review')
    end

    it 'goes back to the main when the account leaves the Fase 2 in the middle of the reading' do
      Autonomia::Agents::Fase2.ligar!(account)
      token = antigo.begin_ingestion!
      Autonomia::Agents::Fase2.desligar!(account)

      antigo.reload.restore_previous_generation!(token)

      expect(antigo.reload.review_status).to eq('needs_review')
    end

    it 'brings a reviewed material back with its verdict' do
      token = source.begin_ingestion!

      source.restore_previous_generation!(token)

      expect(source.reload).to have_attributes(status: 'ready', review_status: 'accepted')
      expect(source.reviewed_at).to be_present
    end
  end

  # #1426 (t4e) — o índice por seção é desta leitura: o resumo o monta ainda na leitura e o mark_ready! o grava junto com o
  # "pronto". A leitura nova sem índice tira o da anterior; a leitura que falha mantém o da geração anterior (os trechos ficam).
  describe 'the summary by section' do
    let(:account) { conta_da_fase2 }
    let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'support') }
    let(:source) { described_class.create!(account: account, agent: agent, source_type: 'pdf', status: :ready) }
    let(:indice) { [{ 'paginas' => [1, 25], 'resumo' => 'Coberturas.', 'temas' => [] }] }

    it 'records the index of this reading with the ready mark' do
      token = source.begin_ingestion!
      source.resumo_por_secao = indice

      source.mark_ready!(token, chunk_count: 1)

      expect(source.reload.metadata[described_class::RESUMO_POR_SECAO]).to eq(indice)
    end

    it 'drops the index of the previous reading when the new one has none' do
      source.update!(metadata: { described_class::RESUMO_POR_SECAO => indice })
      token = source.begin_ingestion!

      source.mark_ready!(token, chunk_count: 1)

      expect(source.reload.metadata).not_to have_key(described_class::RESUMO_POR_SECAO)
    end

    it 'keeps the index of the previous generation when the new reading fails' do
      source.update!(metadata: { described_class::RESUMO_POR_SECAO => indice })
      token = source.begin_ingestion!

      source.mark_failed!(token, 'embedding_down')

      expect(source.reload.metadata[described_class::RESUMO_POR_SECAO]).to eq(indice)
    end

    describe 'in the reading job' do
      let(:token) { source.begin_ingestion! }

      before do
        allow(Autonomia::Agents::Knowledge::Ingestor).to receive(:new)
          .and_return(instance_double(Autonomia::Agents::Knowledge::Ingestor, perform: 1))
      end

      def stub_resumo(&)
        allow(Autonomia::Agents::Knowledge::ResumoPorSecao).to receive(:new) do |source:, token:|
          instance_double(Autonomia::Agents::Knowledge::ResumoPorSecao).tap do |resumo|
            allow(resumo).to receive(:resumir!) { yield(source, token) }
          end
        end
      end

      # Revisão de 30/10: com o resumo depois do "pronto", um deploy no meio deixava o material pronto e sem parecer.
      it 'summarizes while the material is still being read, before the ready mark and the review' do
        ordem = []
        stub_resumo { |fonte, _| ordem << [:resumo, described_class.find(fonte.id).status] }
        revisor = instance_double(Autonomia::Agents::Knowledge::Reviewer)
        allow(Autonomia::Agents::Knowledge::Reviewer).to receive(:new).and_return(revisor)
        allow(revisor).to receive(:review_source!) { ordem << [:revisao, described_class.find(source.id).status] }
        allow(Autonomia::Agents::Knowledge::Reviewer).to receive(:recompute_overall!)

        Autonomia::Agents::Knowledge::ProcessJob.perform_now(source.id, token)

        expect(ordem).to eq([[:resumo, 'processing'], [:revisao, 'ready']])
      end

      # Eval de 30/10: o Revisor regravava o metadata do objeto em memória e apagava o índice (conferência ligada).
      it 'keeps the index through the review and the check of the material' do
        stub_resumo { |fonte, _| fonte.resumo_por_secao = indice }
        parecer = { 'recommendation' => 'aceitar', 'confidence' => 'alta', 'label' => 'boa', 'quality_score' => 90,
                    'summary' => 'Condições gerais.', 'reason' => 'ok' }
        allow_any_instance_of(Autonomia::Agents::Knowledge::Reviewer).to receive(:request_review).and_return(parecer) # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Autonomia::Agents::Material::ConferenciaDoMaterial).to receive(:conferir) # rubocop:disable RSpec/AnyInstance
          .and_return('problema' => nil, 'amostra' => [])
        allow(Autonomia::Agents::Knowledge::Reviewer).to receive(:recompute_overall!)

        Autonomia::Agents::Knowledge::ProcessJob.perform_now(source.id, token)

        source.reload
        expect(source.review_status).to eq('accepted')
        expect(source.metadata[described_class::RESUMO_POR_SECAO]).to eq(indice)
        expect(source.metadata).to have_key('conferencia')
      end
    end
  end
end
