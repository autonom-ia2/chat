require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto do #2487 (Meta aprovar, 02/11: US$ 2 no total do 3a e do 3b): a
# rodada para ao passar de TETO_USD, somado pelo custo registrado em Crm::AiUsageEvent.
#
# #2487 (PR 3b do #2436): o material só do post ou anúncio. O agente da porta REAL (Answerer no formato do comentário) e a
# busca REAL (embeddings de verdade) nos três casos: post do Instagram, post do Facebook e anúncio. Cada cuidado tem um
# arquivo com um fato que só ele sabe. Mede se a resposta usa o arquivo do próprio cuidado (e diz qual), e se a conversa
# normal com o mesmo agente não sabe o fato. Comentários fictícios; nenhum prompt é gravado. A saída vai para EVAL_SAIDA.
module MaterialDoPostEval
  TETO_USD = 1.5
  INSTRUCAO = <<~TEXTO.freeze
    Você é a Loja Maré, de roupas de praia. Atende pelo Instagram e pelo Facebook, com simpatia e frases curtas.
    Vendemos camisetas, bermudas e saídas de praia. Entregamos em todo o Brasil.
  TEXTO
  DO_AGENTE = 'Horário de atendimento da Loja Maré: segunda a sexta, das 9h às 18h.'.freeze
  CASOS = [
    { caso: :post_instagram, network: 'instagram', target_kind: 'post', arquivo: 'tabela-de-medidas.txt',
      material: 'Tabela de medidas da camiseta Maré: P tem 50 cm de largura, M tem 54 cm de largura, G tem 58 cm de largura.',
      comentario: 'Qual a largura da camiseta M?', fato: '54' },
    { caso: :post_facebook, network: 'facebook', target_kind: 'post', arquivo: 'regulamento-do-sorteio.txt',
      material: 'Regulamento do sorteio da Loja Maré: o resultado sai no dia 15/12, ao vivo nos stories.',
      comentario: 'Quando sai o resultado do sorteio?', fato: '15/12' },
    { caso: :anuncio, network: 'instagram', target_kind: 'ad', arquivo: 'cupom-do-anuncio.txt',
      material: 'Cupom deste anúncio: MARE10 dá 10% de desconto na primeira compra, válido até 31/01.',
      comentario: 'Tem cupom de desconto?', fato: 'MARE10' }
  ].freeze
end

RSpec.describe Crm::MetaAds::ComentariosIa::Escrita do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Loja Maré', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: MaterialDoPostEval::INSTRUCAO)
  end
  let(:embed) { Autonomia::Agents::EmbeddingService.new(account: account) }

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    account.enable_features!(Crm::MetaAds::ComentariosIa::Cuidar::FLAG)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    WebMock.allow_net_connect!
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => ENV.fetch('OPENAI_API_KEY') })
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: inbox).perform(connect: true)
    material(MaterialDoPostEval::DO_AGENTE, 'horario.txt')
  end

  after { WebMock.disable_net_connect!(allow_localhost: true) }

  def custo
    Crm::AiUsageEvent.where(account_id: account.id).sum(:cost_estimate).to_f
  end

  # Um arquivo já lido e aceito, com um trecho e o vetor de verdade (sem o IngestJob nem a revisão paga).
  def material(texto, arquivo, care: nil)
    fonte = Autonomia::Agents::Source.create!(account: account, agent: agent, care: care, source_type: 'txt', kind: 'knowledge',
                                              status: :ready, review_status: 'accepted', reference: arquivo)
    vetor = { Autonomia::Agents::Config.embedding_column => embed.embed(texto) }
    Autonomia::Agents::KnowledgeEntry.create!(vetor.merge(account: account, agent: agent, source: fonte, content: texto, chunk_index: 0,
                                                          status: :ready))
  end

  def cuidado(caso)
    care = create(:crm_meta_ads_comment_care, account: account, inbox: inbox, network: caso[:network], target_kind: caso[:target_kind],
                                              offer: nil, note: nil, price_reply: nil, para_quem: 'Quem perguntar')
    material(caso[:material], caso[:arquivo], care: care)
    care
  end

  def comentar(caso, care)
    return if custo > MaterialDoPostEval::TETO_USD

    escrito = described_class.new(care: care, inbox: inbox).escrever(Autonomia::Agents::Answerer::FormatoDoComentario::PRIVADO,
                                                                     comentario: caso[:comentario])
    { caso: caso[:caso], comentario: caso[:comentario], status: escrito.status, texto: escrito.texto, material: escrito.material }
  end

  # O atendimento (operate): a resposta do modelo passa direto, sem o portão que troca o "não sei" pela mensagem padrão.
  def na_conversa(pergunta)
    return if custo > MaterialDoPostEval::TETO_USD

    resultado = Autonomia::Agents::Answerer.new(agent: agent, query: pergunta, trust_instruction: true,
                                                feature: 'meta_ads_comentarios_ia_escreve').answer
    { pergunta: pergunta, resposta: resultado.reply, erro: resultado.error,
      arquivos: Array(resultado.used_knowledge).pluck(:source).compact.uniq }
  end

  def gravar_saida(itens, conversa)
    return if ENV['EVAL_SAIDA'].blank?

    File.write(ENV.fetch('EVAL_SAIDA'), JSON.pretty_generate(itens: itens, conversa_normal: conversa, custo_usd: custo,
                                                             chamadas: Crm::AiUsageEvent.where(account_id: account.id).count))
  end

  it 'cada comentário usa o arquivo do próprio post ou anúncio, e a conversa normal não sabe, dentro do teto' do
    cares = MaterialDoPostEval::CASOS.map { |caso| cuidado(caso) }
    itens = MaterialDoPostEval::CASOS.zip(cares).map { |caso, care| comentar(caso, care) }
    conversa = MaterialDoPostEval::CASOS.map { |caso| na_conversa(caso[:comentario]) }
    gravar_saida(itens, conversa)

    aggregate_failures do
      expect(custo).to be <= MaterialDoPostEval::TETO_USD
      MaterialDoPostEval::CASOS.zip(itens, conversa).each do |caso, item, normal|
        expect(item[:status]).to eq(:escrito), "#{caso[:caso]}: #{item[:status]}"
        expect(item[:texto]).to include(caso[:fato])
        expect(item[:material]).to eq([caso[:arquivo]])
        expect(normal[:erro]).to be_nil
        expect(normal[:resposta]).to be_present
        expect(normal[:resposta]).not_to include(caso[:fato])
        expect(normal[:arquivos]).not_to include(caso[:arquivo])
      end
    end
  end
end
