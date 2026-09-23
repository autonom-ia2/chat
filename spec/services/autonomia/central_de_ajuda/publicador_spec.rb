require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::Publicador do
  let(:raiz) { Pathname.new(Dir.mktmpdir) }
  let(:fonte) { raiz.join('lib') }
  let(:mapa) { raiz.join('mapa.json') }
  let!(:conta) { create(:account) }
  let!(:admin) { create(:user, account: conta, role: :administrator) }

  def artigo(id, titulo, texto = 'Um texto que explica a coisa.')
    cap = id.split('.').first
    FileUtils.mkdir_p(fonte.join(cap))
    File.write(fonte.join(cap, "#{id}-artigo.md"), <<~MD)
      ---
      id: "#{id}"
      titulo: "#{titulo}"
      capitulo: "#{cap}"
      publico: admin
      prioridade: P1
      requer: crm
      assuntos: []
      conferido_em: "2026-09-23"
      ---

      ## O que é

      #{texto}

      ## Veja também

      - [02.01] Onde ficam suas configurações
    MD
  end

  def escrever_mapa
    File.write(mapa, {
      capitulos: [
        { id: '02', titulo: 'Configurações pessoais',
          artigos: [{ id: '02.01', titulo: 'Onde ficam suas configurações' }, { id: '02.02', titulo: 'Seu nome e sua foto' }] }
      ]
    }.to_json)
  end

  def publicar = described_class.new(conta).publicar!

  def escrever_mapa_com_capitulo_03
    File.write(mapa, {
      capitulos: [
        { id: '02', titulo: 'Configurações pessoais',
          artigos: [{ id: '02.01', titulo: 'Onde ficam suas configurações' }, { id: '02.02', titulo: 'Seu nome e sua foto' }] },
        { id: '03', titulo: 'Conta', artigos: [{ id: '03.02', titulo: 'Seu nome e sua foto' }] }
      ]
    }.to_json)
  end

  before do
    described_class.instance_variable_set(:@versao, nil)
    stub_const("#{described_class}::FONTE", fonte)
    stub_const("#{described_class}::MAPA", mapa)
    escrever_mapa
    artigo('02.01', 'Onde ficam suas configurações')
    artigo('02.02', 'Seu nome e sua foto')
  end

  after { FileUtils.remove_entry(raiz) }

  it 'cria o portal da plataforma na conta, com uma categoria por capítulo' do
    resultado = publicar

    expect(resultado.to_h.except(:falhas)).to eq(criados: 2, atualizados: 0, iguais: 0, arquivados: 0)
    portal = Portal.find_by!(slug: 'plataforma')
    expect(portal.account).to eq(conta)
    expect(portal.categories.pluck(:slug, :name)).to eq([['capitulo-02', 'Configurações pessoais']])
  end

  it 'publica cada artigo com título, autor, ordem, descrição, links e meta' do
    publicar

    artigo = Article.find_by!(slug: 'plataforma-02-02')
    expect(artigo).to be_published
    expect(artigo.title).to eq('Seu nome e sua foto')
    expect(artigo.author).to eq(admin)
    expect(artigo.position).to eq(20)
    expect(artigo.description).to eq('Um texto que explica a coisa.')
    expect(artigo.content).to include('[Onde ficam suas configurações](plataforma-02-01)')
    expect(artigo.meta['central']).to include('id' => '02.02', 'requer' => 'crm', 'publico' => 'admin')
  end

  it 'não regrava o que não mudou e atualiza só o que mudou' do
    publicar
    atualizado_em = Article.find_by!(slug: 'plataforma-02-01').updated_at
    artigo('02.02', 'Seu nome e sua foto', 'Texto novo.')

    resultado = publicar

    expect(resultado.to_h.except(:falhas)).to eq(criados: 0, atualizados: 1, iguais: 1, arquivados: 0)
    expect(Article.find_by!(slug: 'plataforma-02-01').updated_at).to eq(atualizado_em)
    expect(Article.find_by!(slug: 'plataforma-02-02').description).to eq('Texto novo.')
  end

  it 'arquiva o artigo que saiu do repositório, sem apagar, e o republica se ele voltar' do
    publicar
    File.delete(fonte.join('02', '02.02-artigo.md'))

    expect(publicar.arquivados).to eq(1)
    expect(Article.find_by!(slug: 'plataforma-02-02')).to be_archived

    artigo('02.02', 'Seu nome e sua foto')
    expect(publicar.atualizados).to eq(1)
    expect(Article.find_by!(slug: 'plataforma-02-02')).to be_published
  end

  it 'não arquiva o artigo cujo arquivo quebrou: registra a falha e mantém o que está no ar' do
    publicar
    File.write(fonte.join('02', '02.02-artigo.md'), 'sem cabeçalho')

    resultado = publicar

    expect(resultado).not_to be_ok
    expect(resultado.falhas.size).to eq(1)
    expect(resultado.arquivados).to eq(0)
    expect(Article.find_by!(slug: 'plataforma-02-02')).to be_published
  end

  it 'mantém a ordem do id quando o artigo muda de capítulo' do
    escrever_mapa_com_capitulo_03
    publicar
    artigo('03.02', 'Seu nome e sua foto')
    File.delete(fonte.join('02', '02.02-artigo.md'))
    publicar
    movido = Article.find_by!(slug: 'plataforma-03-02')
    caminho = fonte.join('03', '03.02-artigo.md')
    File.write(caminho, File.read(caminho).sub('capitulo: "03"', 'capitulo: "02"'))

    publicar

    expect(movido.reload.category.slug).to eq('capitulo-02')
    expect(movido.position).to eq(20)
  end

  it 'desiste sem publicar quando outra publicação segura o lock' do
    # Outra sessão do Postgres, como a outra instância do blue/green (os testes dividem a mesma conexão).
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    outra = PG.connect(dbname: cfg[:database], host: cfg[:host], port: cfg[:port], user: cfg[:username], password: cfg[:password])
    outra.exec("SELECT pg_advisory_lock(#{described_class::LOCK_NS}, #{conta.id})")

    expect(publicar).to be_nil
    expect(Portal.find_by(slug: 'plataforma')).to be_nil
  ensure
    outra&.close
  end

  it 'preserva outras chaves de meta do artigo' do
    publicar
    artigo_publicado = Article.find_by!(slug: 'plataforma-02-02')
    artigo_publicado.update!(meta: artigo_publicado.meta.merge('outra' => 'chave'))
    artigo('02.02', 'Seu nome e sua foto', 'Texto novo.')

    publicar

    expect(artigo_publicado.reload.meta).to include('outra' => 'chave')
  end

  it 'não toca artigo de outro portal da conta' do
    outro = create(:portal, account: conta)
    solto = create(:article, portal: outro, account: conta, author: admin, slug: 'meu-artigo', status: :published)

    publicar

    expect(solto.reload).to be_published
  end

  it 'recusa publicar quando o portal "plataforma" é de outra conta' do
    create(:portal, slug: 'plataforma')

    expect { publicar }.to raise_error(described_class::Conflito, a_string_including('já existe na conta'))
  end

  it 'recusa conta sem administrador para assinar' do
    AccountUser.where(account: conta).destroy_all

    expect { publicar }.to raise_error(described_class::Conflito, a_string_including('sem administrador'))
  end

  describe '.garantir_async' do
    around do |exemplo|
      cache_original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      exemplo.run
    ensure
      Rails.cache = cache_original
    end

    it 'enfileira uma vez e para de enfileirar depois de publicado' do
      expect { 2.times { described_class.garantir_async } }
        .to have_enqueued_job(Autonomia::CentralDeAjuda::PublicarJob).exactly(:once)

      described_class.new(conta).publicar!

      expect { described_class.garantir_async }.not_to have_enqueued_job(Autonomia::CentralDeAjuda::PublicarJob)
    end
  end

  describe '.conta' do
    it 'é a conta mais antiga enquanto o portal não existe' do
      create(:account)

      expect(described_class.conta).to eq(Account.order(:id).first)
    end

    it 'é a conta dona do portal depois que ele existe' do
      outra = create(:account)
      create(:portal, account: outra, slug: 'plataforma')

      expect(described_class.conta).to eq(outra)
    end
  end
end
