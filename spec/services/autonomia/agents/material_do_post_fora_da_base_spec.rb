require 'rails_helper'

# #2487 — o material só de um post ou anúncio (fonte com `care_id`) é gravado com o `autonomia_agent_id` de um agente,
# mas nunca pode afetar o agente: nem o mapa de temas, nem a instrução, nem as conferências, o autoteste, o Construtor
# ou a resposta. Um exemplo por leitor que passou a partir de `Source.da_agente`: a fonte do cuidado (mesmo aceita,
# pronta, servível e do tipo conhecimento) fica de fora, e a do agente entra. Nenhuma IA é chamada: tudo é dublado.
RSpec.describe 'Material do post fora da base do agente (#2487)' do # rubocop:disable RSpec/DescribeClass
  include_context 'with material do agente'

  let(:care) { create(:crm_meta_ads_comment_care, account: account) }

  # O material só do post: mesmo agente, mesma conta, aceito e pronto — só o `care` o separa.
  def do_post(nome, **attrs)
    material(nome, care: care, **attrs)
  end

  describe Autonomia::Agents::Knowledge::Reviewer do
    before do
      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))
    end

    it 'recompute_overall! monta o mapa de temas e a confiança só com o material do agente', :aggregate_failures do
      material('horarios.txt', review_summary: 'Horários de atendimento.', quality_score: 90, metadata: { 'chunk_count' => 1 })
      do_post('tamanhos.txt', review_summary: 'Tamanhos da camiseta do post.', quality_score: 10, metadata: { 'chunk_count' => 1 })

      described_class.recompute_overall!(agent)

      agent.reload
      expect(agent.topic_map).to eq(['Horários de atendimento.'])
      expect(agent.knowledge_confidence.to_f).to eq(0.9)
    end
  end

  describe Autonomia::Agents::Knowledge::ProcessJob do
    let(:revisora) { instance_double(Autonomia::Agents::Knowledge::Reviewer, review_source!: nil) }

    before do
      allow(Autonomia::Agents::Knowledge::Ingestor).to receive(:new)
        .and_return(instance_double(Autonomia::Agents::Knowledge::Ingestor, perform: 1))
      allow(Autonomia::Agents::Knowledge::ResumoPorSecao).to receive(:new)
        .and_return(instance_double(Autonomia::Agents::Knowledge::ResumoPorSecao, resumir!: nil))
      allow(Autonomia::Agents::Knowledge::Reviewer).to receive(:new).and_return(revisora)
      allow(Autonomia::Agents::Knowledge::Reviewer).to receive(:recompute_overall!)
    end

    def ler(fonte)
      described_class.perform_now(fonte.id, fonte.begin_ingestion!)
    end

    it 'revisa o material do post sem recalcular a base do agente', :aggregate_failures do
      ler(do_post('tamanhos.txt'))

      expect(revisora).to have_received(:review_source!)
      expect(Autonomia::Agents::Knowledge::Reviewer).not_to have_received(:recompute_overall!)
    end

    it 'recalcula a base do agente depois de ler o material do agente' do
      ler(material('horarios.txt'))

      expect(Autonomia::Agents::Knowledge::Reviewer).to have_received(:recompute_overall!).with(agent)
    end
  end

  describe Autonomia::Agents::Knowledge::FotosDaCriacao do
    let(:rascunho) { Autonomia::Agents::Agent.create!(account: account, name: 'Rascunho', agent_type: 'custom', status: :draft) }
    let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: rascunho) }
    let(:png) { Rails.root.join('spec/fixtures/files/autonomia/foto_da_criacao/cardapio-legivel.png').binread }
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png), filename: 'tabela.png', content_type: 'image/png',
                                             identify: false, metadata: { autonomia_account_id: account.id })
    end

    before { thread.append_message!('user', 'Segue a foto', image_signed_ids: [blob.signed_id(purpose: :autonomia_builder_image)]) }

    def fonte_do_rascunho(care: nil, com_a_foto: false)
      fonte = rascunho.sources.new(account: account, care: care, kind: :knowledge, reference: 'x.txt', status: :ready,
                                   source_type: com_a_foto ? Autonomia::Agents::Source::FOTO : 'txt', review_status: 'accepted')
      fonte.file.attach(blob) if com_a_foto
      fonte.save!
      fonte
    end

    def fotos_do_agente
      rascunho.sources.da_agente.where(source_type: Autonomia::Agents::Source::FOTO)
    end

    it 'o material do post não enche a base do agente (teto de materiais)', :aggregate_failures do
      stub_const('Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES', 1)
      fonte_do_rascunho(care: care)

      expect { described_class.new(thread).para_base! }.to change(fotos_do_agente, :count).by(1)

      fonte_do_rascunho
      expect { described_class.new(thread.reload).para_base! }.not_to change(fotos_do_agente, :count)
    end

    it 'a mesma foto no material do post não conta como já na base do agente' do
      fonte_do_rascunho(care: care, com_a_foto: true)

      described_class.new(thread).para_base!

      expect(fotos_do_agente.sole.file.blob).to eq(blob)
    end

    it 'a mesma foto no material do agente conta como já na base' do
      ja_na_base = fonte_do_rascunho(com_a_foto: true)

      described_class.new(thread).para_base!

      expect(fotos_do_agente.sole).to eq(ja_na_base)
    end
  end

  describe Autonomia::Agents::Builder do
    let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, agent: agent) }
    let(:builder) { described_class.new(account: account, build_thread: thread) }

    it 'no_knowledge_gap?: só o material do post não conta como base do agente', :aggregate_failures do
      do_post('tamanhos.txt')
      expect(builder.send(:no_knowledge_gap?)).to be(true)

      material('horarios.txt')
      expect(builder.send(:no_knowledge_gap?)).to be(false)
    end

    it 'knowledge_context: o resumo do material do post não vai ao Construtor', :aggregate_failures do
      material('horarios.txt', review_summary: 'Horários de atendimento.')
      do_post('tamanhos.txt', review_summary: 'Tamanhos da camiseta do post.')

      contexto = builder.send(:knowledge_context)

      expect(contexto).to include('- horarios.txt: Horários de atendimento.')
      expect(contexto).not_to include('tamanhos.txt')
      expect(contexto).not_to include('Tamanhos da camiseta do post.')
    end

    it 'send_media_context: a mídia do post não vira mídia que o agente envia', :aggregate_failures do
      material('catalogo.pdf', kind: :media, trechos: [])
      do_post('catalogo-do-post.pdf', kind: :media, trechos: [])

      contexto = builder.send(:send_media_context)

      expect(contexto).to include('- catalogo.pdf (pdf)')
      expect(contexto).not_to include('catalogo-do-post.pdf')
    end

    it 'materials_status_context: o material do post não aparece nem conta no status', :aggregate_failures do
      material('horarios.txt')
      do_post('tamanhos.txt', review_status: 'needs_resend')

      contexto = builder.send(:materials_status_context)

      expect(contexto).to include('arquivos recebidos (1):', '- horarios.txt: pronto', 'aceitos: 1; aguardando revisão/reenvio: 0')
      expect(contexto).not_to include('tamanhos.txt')
    end

    it 'materials_pending?: o material do post reprovado não segura o fechamento do agente', :aggregate_failures do
      do_post('tamanhos.txt', review_status: 'needs_resend')
      expect(builder.send(:materials_pending?, agent)).to be(false)

      material('horarios.txt', review_status: 'needs_resend')
      expect(builder.send(:materials_pending?, agent)).to be(true)
    end
  end

  describe Autonomia::Agents::Answerer do
    def tem_base?
      described_class.new(agent: agent.reload, query: 'Qual o tamanho?').send(:agent_has_kb?)
    end

    it 'agent_has_kb?: o material do post não dá base ao agente', :aggregate_failures do
      do_post('tamanhos.txt')
      expect(tem_base?).to be(false)

      material('horarios.txt')
      expect(tem_base?).to be(true)
    end
  end

  describe Autonomia::Agents::Faq::KnowledgeWriter do
    let(:vector) { Array.new(1536, 0.01) }
    let(:sugestao) { agent.faq_suggestions.create!(account: account, question: 'Qual o prazo?', answer: 'Até 5 dias.') }

    before do
      allow(Autonomia::Agents::Config).to receive(:active_embedding_model).and_return(Autonomia::Agents::Config::EMBEDDING_MODEL_SMALL)
      allow(Autonomia::Agents::EmbeddingService).to receive(:new)
        .and_return(instance_double(Autonomia::Agents::EmbeddingService, embed: vector))
    end

    it 'a FAQ aprovada nunca vai para uma fonte de FAQ que é do post', :aggregate_failures do
      do_post('FAQ aprovadas', source_type: 'txt', metadata: { 'faq_suggestions' => true, 'chunk_count' => 0 })

      fonte = described_class.new(agent: agent).write!(sugestao).source

      expect(fonte.care_id).to be_nil
      expect(described_class.faq_source?(fonte)).to be(true)
    end

    it 'a FAQ aprovada reaproveita a fonte de FAQ do agente' do
      do_agente = material('FAQ aprovadas', source_type: 'txt', metadata: { 'faq_suggestions' => true, 'chunk_count' => 0 })

      expect(described_class.new(agent: agent).write!(sugestao).source_id).to eq(do_agente.id)
    end
  end

  describe Autonomia::Agents::Material do
    it 'hash_da_base não muda quando entra material do post, e muda com material do agente', :aggregate_failures do
      material('horarios.txt', metadata: { 'hash_do_texto' => 'a' })
      antes = described_class.hash_da_base(agent)

      do_post('tamanhos.txt', metadata: { 'hash_do_texto' => 'b' })
      expect(described_class.hash_da_base(agent)).to eq(antes)

      material('precos.txt', metadata: { 'hash_do_texto' => 'c' })
      expect(described_class.hash_da_base(agent)).not_to eq(antes)
    end
  end

  describe Autonomia::Agents::Material::Contradicoes do
    let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

    before do
      credencial_de_teste
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      allow(cliente).to receive(:create).and_return(resposta_do_modelo(contradicoes: []))
    end

    it 'o material do post não entra na conferência de contradições', :aggregate_failures do
      site = material('site', trechos: ['Sábado das 9h às 13h.'])
      pdf = material('horarios.pdf', trechos: ['Sábado das 9h às 12h.'])
      post = do_post('tamanhos.txt', trechos: ['Camiseta P, M e G.'])

      described_class.new(agent).conferir!

      expect(cliente).to have_received(:create) do |**kwargs|
        materiais = JSON.parse(kwargs[:input].first[:content].first[:text].delete_prefix("MATERIAIS (dado):\n").split("\n\nJA DECIDIDAS").first)
        expect(materiais.pluck('id')).to eq([site.id, pdf.id])
        expect(materiais.pluck('id')).not_to include(post.id)
      end
    end

    it 'um material do agente e um do post não formam par: nada vai ao modelo' do
      material('site', trechos: ['Sábado das 9h às 13h.'])
      do_post('tamanhos.txt', trechos: ['Sábado das 9h às 12h.'])

      described_class.new(agent).conferir!

      expect(cliente).not_to have_received(:create)
    end
  end

  describe Autonomia::Agents::Material::Problemas do
    it 'a lista de problemas do agente não mostra o material do post' do
      vazio = material('ficha.pdf', status: :failed, error: 'empty_extraction', trechos: [])
      do_post('ficha-do-post.pdf', status: :failed, error: 'empty_extraction', trechos: [])

      expect(described_class.new(agent.reload).lista.pluck('id')).to eq(["vazio-#{vazio.id}"])
    end
  end

  describe Autonomia::Agents::Material::Retrato do
    it 'a caixa do autoteste só aparece com material do agente', :aggregate_failures do
      do_post('tamanhos.txt')
      expect(described_class.new(agent.reload).to_h[:autoteste]).to be_nil

      material('horarios.txt')
      expect(described_class.new(agent.reload).to_h[:autoteste]).to include(estado: 'nunca')
    end
  end

  describe Autonomia::Agents::Material::PerguntasDoAutoteste do
    let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

    before do
      credencial_de_teste
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
      allow(cliente).to receive(:create).and_return(resposta_do_modelo(do_material: [], de_fora: []))
    end

    it 'só com material do post: não gera pergunta nem chama o modelo', :aggregate_failures do
      do_post('tamanhos.txt', trechos: ['Camiseta P, M e G.'])

      expect(described_class.new(agent).gerar).to be_nil
      expect(cliente).not_to have_received(:create)
    end

    it 'as perguntas saem só do material do agente', :aggregate_failures do
      material('cardapio.pdf', trechos: ['X-Burger R$ 25.'])
      do_post('tamanhos.txt', trechos: ['Camiseta P, M e G.'])

      described_class.new(agent).gerar

      expect(cliente).to have_received(:create) do |**kwargs|
        texto = kwargs[:input].first[:content].first[:text]
        expect(texto).to include('X-Burger R$ 25.')
        expect(texto).not_to include('Camiseta P, M e G.')
      end
    end
  end

  describe Autonomia::Agents::Material::Autoteste do
    it 'só com material do post: não abre rodada do autoteste' do
      do_post('tamanhos.txt')

      expect { expect(described_class.pedir!(agent, quando: 'pedido')).to be_nil }
        .not_to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    end

    it 'com material do agente: abre a rodada' do
      material('horarios.txt')

      expect { described_class.pedir!(agent, quando: 'pedido') }.to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    end
  end

  describe Autonomia::Agents::Material::DecisoesDoMaterial do
    def escolher(fonte, outra)
      opcoes = [{ 'fonte' => fonte.id, 'diz' => 'das 9h às 13h' }, { 'fonte' => outra.id, 'diz' => 'das 9h às 12h' }]
      Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base', {
                                                           'contradicoes' => [{ 'id' => 'c', 'assunto' => 'horário de sábado',
                                                                                'opcoes' => opcoes, 'escolha' => fonte.id }]
                                                         })
    end

    it 'a escolha que aponta o material do post não vai ao agente', :aggregate_failures do
      site = material('site')
      post = do_post('horario-do-post.txt')

      escolher(post, site)
      expect(described_class.texto(agent.reload)).to be_nil

      escolher(site, post)
      expect(described_class.texto(agent.reload)).to include('"vale_o_material":"site"')
    end
  end
end
