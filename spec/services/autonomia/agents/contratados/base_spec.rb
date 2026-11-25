require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::Base do
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Desde 2010.' }
  end
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end
  let(:embedder) { instance_double(Autonomia::Agents::EmbeddingService) }
  let(:tres_blocos) do
    "<!-- fonte: exemplo -->\n\n### Cláusula 1\n\nTexto um.\n\n### Cláusula 2\n\nTexto dois.\n### Cláusula 3\nTexto três.\n"
  end

  let(:pasta) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.remove_entry(pasta) }

  before do
    coluna = Autonomia::Agents::Config.embedding_column(Autonomia::Agents::Config.active_embedding_model)
    dimensao = coluna == Autonomia::Agents::Config::EMBEDDING_LARGE_COLUMN ? 3072 : 1536
    allow(embedder).to receive(:embed_batch) { |textos| textos.map { Array.new(dimensao, 0.01) } }
    allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedder)
    pasta.join('clausulas.md').write(tres_blocos)
  end

  def entradas
    Autonomia::Agents::KnowledgeEntry.where(autonomia_agent_id: agente.id)
  end

  it 'fatia nos blocos que começam por ### e deixa de fora o que vem antes do primeiro' do
    blocos = described_class.blocos(tres_blocos)
    expect(blocos.size).to eq(3)
    expect(blocos.first).to eq("### Cláusula 1\n\nTexto um.")
    expect(blocos.last).to eq("### Cláusula 3\nTexto três.")
  end

  it 'um texto com 3 blocos vira 3 entradas, na fonte de sistema aceita e pronta' do
    described_class.semear!(agente, pasta: pasta)

    fonte = described_class.fontes(agente).sole
    expect(fonte).to have_attributes(source_type: 'md', kind: 'knowledge', reference: 'Base oficial Universal',
                                     status: 'ready', review_status: 'accepted')
    expect(fonte.metadata).to include('contratado_base' => true)
    expect(entradas.ready.where(source_id: fonte.id).order(:chunk_index).pluck(:content))
      .to eq(["### Cláusula 1\n\nTexto um.", "### Cláusula 2\n\nTexto dois.", "### Cláusula 3\nTexto três."])
    expect(agente.reload.config[Autonomia::Agents::Contratados::BASE_VERSAO]).to eq(described_class.versao_de(pasta))
  end

  it 'grava o vetor na coluna do modelo ativo' do
    described_class.semear!(agente, pasta: pasta)
    coluna = Autonomia::Agents::Config.embedding_column(Autonomia::Agents::Config.active_embedding_model)
    expect(entradas.where(coluna => nil)).to be_empty
  end

  it 'a segunda semeadura apaga as entradas e a fonte antigas' do
    described_class.semear!(agente, pasta: pasta)
    antigas = entradas.pluck(:id)
    fonte_antiga = described_class.fontes(agente).sole

    described_class.semear!(agente, pasta: pasta)

    expect(entradas.count).to eq(3)
    expect(entradas.where(id: antigas)).to be_empty
    expect(Autonomia::Agents::Source.exists?(fonte_antiga.id)).to be(false)
    expect(described_class.fontes(agente).count).to eq(1)
  end

  it 'não toca o material que a corretora mandou' do
    dela = agente.sources.create!(account: account, source_type: 'txt', reference: 'faq.txt', status: :ready,
                                  review_status: 'accepted')
    agente.knowledge_entries.create!(account: account, source: dela, content: 'Material da corretora.')

    2.times { described_class.semear!(agente, pasta: pasta) }

    expect(entradas.where(source_id: dela.id).pluck(:content)).to eq(['Material da corretora.'])
  end

  it 'a versão muda quando o arquivo muda' do
    antes = described_class.versao_de(pasta)
    pasta.join('clausulas.md').write("#{tres_blocos}\nMais uma linha.\n")
    expect(described_class.versao_de(pasta)).not_to eq(antes)
    expect(antes.length).to eq(16)
  end

  it 'a versão do deploy é a dos arquivos de base/ do modelo' do
    expect(described_class::VERSAO).to eq(described_class.versao_de(described_class::PASTA))
    expect(described_class.arquivos(described_class::PASTA).map { |a| a.basename.to_s })
      .to eq(%w[condicoes_gerais.md folheto_de_produtos.md])
  end

  it 'os arquivos de base/ viram um bloco por título ###' do
    arquivos = described_class.arquivos(described_class::PASTA)
    titulos = arquivos.sum { |arquivo| arquivo.read.each_line.count { |linha| linha.start_with?('### ') } }
    blocos = arquivos.flat_map { |arquivo| described_class.blocos(arquivo.read) }
    expect(blocos.size).to eq(titulos)
    expect(blocos).to all(start_with('### '))
  end

  it 'em dia: versão do deploy e trechos prontos' do
    expect(described_class.em_dia?(agente)).to be(false)
    described_class.semear!(agente, pasta: pasta)
    described_class.gravar_versao!(agente, described_class::VERSAO)
    expect(described_class.em_dia?(agente.reload)).to be(true)

    entradas.delete_all
    expect(described_class.em_dia?(agente)).to be(false)
  end

  it 'semear se preciso: em dia, não chama o embedding' do
    described_class.semear!(agente, pasta: pasta)
    described_class.gravar_versao!(agente, described_class::VERSAO)

    expect(described_class.semear_se_preciso!(agente.reload)).to be(false)
    expect(embedder).to have_received(:embed_batch).once
  end

  it 'semear se preciso: agente apagado ou que não é contratado, nada' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')
    agente.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.semear_se_preciso!(agente)).to be(false)
    expect(described_class.semear_se_preciso!(comum)).to be(false)
    expect(embedder).not_to have_received(:embed_batch)
  end

  it 'falha do embedding: a base anterior fica como estava' do
    described_class.semear!(agente, pasta: pasta)
    antigas = entradas.pluck(:id)
    allow(embedder).to receive(:embed_batch).and_raise(Autonomia::Agents::EmbeddingService::EmbeddingError, 'rede')

    expect { described_class.semear!(agente, pasta: pasta) }.to raise_error(Autonomia::Agents::EmbeddingService::EmbeddingError)
    expect(entradas.pluck(:id)).to match_array(antigas)
  end
end
