require 'rails_helper'

# #2487 — o material só de um post ou anúncio: só a resposta a um comentário daquele cuidado lê.
RSpec.describe Autonomia::Agents::Retriever do
  let(:account) { create(:account) }
  let(:vector) { Array.new(1536) { 0.01 } }
  let(:agente_ig) { agente(account, 'Atendente IG') }
  let(:agente_fb) { agente(account, 'Atendente FB') }
  let(:post) { create(:crm_meta_ads_comment_care, account: account) }
  let(:anuncio) { create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', network: 'both') }

  before do
    service = instance_double(Autonomia::Agents::EmbeddingService)
    allow(service).to receive(:embed).and_return(vector)
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(service)
  end

  def agente(conta, nome, config: {})
    Autonomia::Agents::Agent.create!(account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.', config: config)
  end

  def material(agent, conteudo, care: nil, embedding: vector, conta: agent.account)
    fonte = Autonomia::Agents::Source.create!(account: conta, agent: agent, care: care, source_type: 'txt', kind: 'knowledge',
                                              status: :ready, reference: "#{conteudo}.txt")
    Autonomia::Agents::KnowledgeEntry.create!(account: conta, agent: agent, source: fonte, content: conteudo,
                                              chunk_index: 0, metadata: {}, embedding: embedding)
  end

  def lidos(agent, care_id: nil)
    described_class.new(agent: agent, care_id: care_id).retrieve('tamanho prazo entrega').map(&:content)
  end

  shared_examples 'o escopo do cuidado' do
    it 'never reads post or ad material in a normal turn' do
      material(agente_ig, 'base da loja')
      material(agente_ig, 'tamanhos do post', care: post)
      material(agente_ig, 'prazo do anuncio', care: anuncio)

      expect(lidos(agente_ig)).to eq(['base da loja'])
    end

    it 'never reads care material through the lexical path in a normal turn' do
      material(agente_ig, 'base da loja')
      material(agente_ig, 'tamanho prazo entrega do post', care: post, embedding: nil)

      expect(lidos(agente_ig)).to eq(['base da loja'])
    end

    it 'reads the post material with the agent material in a comment turn of that post' do
      material(agente_ig, 'base da loja')
      material(agente_ig, 'tamanhos do post', care: post)

      expect(lidos(agente_ig, care_id: post.id)).to contain_exactly('base da loja', 'tamanhos do post')
    end

    it 'lets both ports of an ad read its material, whichever port attached it' do
      material(agente_ig, 'prazo do anuncio', care: anuncio)
      material(agente_fb, 'base da pagina')

      expect(lidos(agente_ig, care_id: anuncio.id)).to eq(['prazo do anuncio'])
      expect(lidos(agente_fb, care_id: anuncio.id)).to contain_exactly('base da pagina', 'prazo do anuncio')
    end

    it 'does not show the material of care X in care Y' do
      material(agente_ig, 'tamanhos do post', care: post)
      material(agente_ig, 'prazo do anuncio', care: anuncio)

      expect(lidos(agente_ig, care_id: post.id)).to eq(['tamanhos do post'])
      expect(lidos(agente_ig, care_id: anuncio.id)).to eq(['prazo do anuncio'])
    end

    it 'never reads material of another account, even with its care id' do
      outra = create(:account)
      de_fora = create(:crm_meta_ads_comment_care, account: outra, target_kind: 'ad', network: 'both')
      material(agente(outra, 'Outro'), 'segredo de outra conta', care: de_fora)
      material(agente_ig, 'base da loja')

      expect(lidos(agente_ig, care_id: de_fora.id)).to eq(['base da loja'])
    end

    it 'leaves out care material the reviewer rejected' do
      material(agente_fb, 'prazo do anuncio', care: anuncio).source.update!(review_status: 'needs_resend')
      material(agente_ig, 'base da loja')

      expect(lidos(agente_ig, care_id: anuncio.id)).to eq(['base da loja'])
    end

    it 'reads only the care material when the agent has no base' do
      sem_base = agente(account, 'Sem base', config: { 'with_knowledge' => false })
      material(sem_base, 'resto de uma base antiga')
      material(sem_base, 'tamanhos do post', care: post)

      expect(lidos(sem_base, care_id: post.id)).to eq(['tamanhos do post'])
    end

    it 'keeps reading the agent passages that have no source' do
      Autonomia::Agents::KnowledgeEntry.create!(account: account, agent: agente_ig, content: 'trecho sem fonte', chunk_index: 0,
                                                metadata: {}, embedding: vector)

      expect(lidos(agente_ig)).to eq(['trecho sem fonte'])
    end
  end

  it_behaves_like 'o escopo do cuidado'

  # #2810: a busca por palavra lê o mesmo escopo.
  context 'with rag_busca_hibrida on' do
    before { account.enable_features!('rag_busca_hibrida') }

    it_behaves_like 'o escopo do cuidado'
  end
end
