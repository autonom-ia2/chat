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
  let!(:hook) do
    # A chave da conta é de mentira: a validação do gancho não chama o provedor.
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
  end

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

  it 'semeia com a chave da própria conta, passada ao serviço (sem resolver de novo)' do
    expect(described_class.semear!(agente, pasta: pasta)).to be(true)
    expect(Autonomia::Agents::EmbeddingService).to have_received(:new)
      .with(hash_including(credencial: hash_including(api_key: 'chave-da-conta-teste', source: :hook)))
  end

  it 'conta sem a própria chave, com a chave da instalação configurada: não chama o provedor nem grava nada' do
    hook.destroy!
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao-teste')

    expect(described_class.semear!(agente, pasta: pasta)).to eq(described_class::SEM_CHAVE_DA_CONTA)
    expect(described_class.semear_se_preciso!(agente)).to eq(described_class::SEM_CHAVE_DA_CONTA)

    expect(Autonomia::Agents::EmbeddingService).not_to have_received(:new)
    expect(described_class.fontes(agente)).to be_empty
    expect(entradas).to be_empty
    expect(agente.reload.config).not_to have_key(Autonomia::Agents::Contratados::BASE_VERSAO)
  end

  it 'trecho sem vetor: não troca a base nem grava a versão' do
    described_class.semear!(agente, pasta: pasta)
    antigas = entradas.pluck(:id)
    versao = agente.reload.config[Autonomia::Agents::Contratados::BASE_VERSAO]
    pasta.join('clausulas.md').write("#{tres_blocos}\n### Cláusula 4\nTexto quatro.\n")
    allow(embedder).to receive(:embed_batch) { |textos| textos.map.with_index { |_t, i| i.zero? ? [] : [0.01] } }

    expect(described_class.semear!(agente, pasta: pasta)).to eq(described_class::BASE_PARCIAL)
    expect(entradas.pluck(:id)).to match_array(antigas)
    expect(agente.reload.config[Autonomia::Agents::Contratados::BASE_VERSAO]).to eq(versao)
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
      .to eq(%w[condicoes_gerais.md folheto_de_produtos.md material_de_venda.md])
  end

  it 'os arquivos de base/ viram um bloco por título ###' do
    arquivos = described_class.arquivos(described_class::PASTA)
    titulos = arquivos.sum { |arquivo| arquivo.read.each_line.count { |linha| linha.start_with?('### ') } }
    blocos = arquivos.flat_map { |arquivo| described_class.blocos(arquivo.read) }
    expect(blocos.size).to eq(titulos)
    expect(blocos).to all(start_with('### '))
  end

  describe 'o material de venda não passa canal de venda da Universal (#3226)' do
    let(:material) { described_class::PASTA.join('material_de_venda.md').read(encoding: 'UTF-8') }
    let(:caminhos_permitidos) do
      %w[app/ asistencia/ reembolso-requisitos reembolso-checklist condicoes-gerais]
        .map { |caminho| "https://www.universal-assistance.com/br/#{caminho}" }
    end

    it 'sem televendas nem WhatsApp de vendas' do
      ['0800 333 3000', '2107-0349', '2107 0349', '551121070349', 'wa.me'].each do |canal|
        expect(material).not_to include(canal)
      end
    end

    it 'todo link do site da Universal é de assistência, app, reembolso ou condições gerais, nunca a página inicial' do
      links = material.each_line.flat_map(&:split).select { |palavra| palavra.include?('universal-assistance.com') }
      expect(links).not_to be_empty
      expect(links).to all(satisfy { |link| link.start_with?(*caminhos_permitidos) })
    end

    it 'vídeo só os três passo a passo oficiais conferidos, nunca a página do canal nem propaganda' do
      conferidos = %w[KNaqJzSUZbE 5rqzlIByuUg LU8TIYR5XpE].map { |id| "https://www.youtube.com/watch?v=#{id}" }
      videos = material.each_line.flat_map(&:split).select { |palavra| palavra.include?('youtube.com') || palavra.include?('youtu.be') }
      expect(videos.uniq).to match_array(conferidos)
    end

    it 'cada vídeo está no bloco que a busca traz para a pergunta, com a ressalva dele' do
      blocos = described_class.blocos(material)
      bloco = ->(titulo) { blocos.find { |texto| texto.start_with?("### Universal Assistance: #{titulo}") } }

      expect(bloco.call('reembolso, como pedir')).to include('LU8TIYR5XpE', '2023', 'despesa médica', 'reembolso-checklist')
      expect(bloco.call('app e serviços digitais')).to include('KNaqJzSUZbE', '5rqzlIByuUg', 'Argentina')
      expect(bloco.call('o que fazer na hora do problema')).to include('KNaqJzSUZbE', 'Argentina')
      expect(material).not_to include('reembolso.br@')
    end
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
