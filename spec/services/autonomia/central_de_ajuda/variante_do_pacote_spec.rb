require 'rails_helper'

# #1802: a conta de um pacote lê os artigos da Central com as palavras dele; as outras leem o artigo de sempre.
RSpec.describe Autonomia::CentralDeAjuda::VarianteDoPacote do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:dona) { create(:account) }
  let(:portal) { create(:portal, slug: 'plataforma', account: dona) }

  def artigo(id, titulo)
    create(:article, account: dona, portal: portal, slug: "plataforma-#{id.tr('.', '-')}", title: titulo,
                     description: "Sobre #{titulo}", content: 'Texto do artigo base.', status: :published,
                     meta: { 'central' => { 'id' => id, 'me_leve_ate_la' => { 'rota' => 'crm_kanban_index' },
                                            'video' => { 'arquivo' => "/central-de-ajuda/videos/#{id}.mp4" } } })
  end

  def leitura_de(account)
    admin = create(:user, account: account, role: :administrator)
    Autonomia::CentralDeAjuda::Leitura.new(account: account, account_user: account.account_users.find_by(user: admin))
  end

  def conta(nicho_escolhido, perfil = nil)
    create(:account, internal_attributes: { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil }.compact)
  end

  before do
    artigo('10.04', 'Ganhar, perder, reabrir e arquivar')
    artigo('10.03', 'Mover card, a gaveta e a timeline')
  end

  it 'composes every variant in the repository against its base article' do
    [%w[seguros], %w[seguros seguros/corretora]].each do |camadas|
      variantes = described_class.montar(camadas)

      expect(variantes).not_to be_empty
      variantes.each_value do |variante|
        expect(variante.fonte.conteudo).to include('## O que é')
        expect(variante.fonte.titulo).to be_present
      end
    end
  end

  it 'gives the brokerage the words of its screen, without the general video' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      leitura = leitura_de(conta('seguros', 'corretora'))
      fechar = leitura.artigo('10.04')

      expect(fechar.title).to eq('Fechou o seguro, não fechou, reabrir e arquivar')
      expect(fechar.content).to include('**Marcar: fechou o seguro**').and include('## Veja também')
      expect(fechar.content).not_to include('Marcar como ganho')
      expect(leitura.central(fechar)).to include('pacote' => 'seguros', 'video' => nil)
      expect(leitura.resumo(fechar)).to include(video: false, rota: 'crm_kanban_index')

      mover = leitura.artigo('10.03')
      expect(mover.content).to include('**Fechou o seguro**', '**Seguro**, **Agenda**')
      expect(leitura.central(mover)['pacote']).to eq('seguros/corretora')
    end
  end

  it 'never gives the brokerage words to another kind of insurance account' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      leitura = leitura_de(conta('seguros', 'seguradora'))
      mover = leitura.artigo('10.03')

      expect(leitura.central(mover)['pacote']).to eq('seguros')
      expect(mover.content).to include('**Fechou o seguro**')
      expect(mover.content).not_to include('**Seguro**, **Agenda**')
    end
  end

  it 'speaks of the plan, not the insurance, to a health and benefits account' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      leitura = leitura_de(conta('seguros', 'saude_beneficios'))
      fechar = leitura.artigo('10.04')

      expect(fechar.title).to eq('Implantado, não fechou, reabrir e arquivar')
      expect(fechar.content).to include('**Marcar como implantado**')
      expect(fechar.content).not_to include('seguro')
      expect(leitura.central(fechar)['pacote']).to eq('seguros/saude_beneficios')
    end
  end

  it 'finds the variant by the words of the brokerage' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      resultado = leitura_de(conta('seguros', 'corretora')).buscar('fechou o seguro')

      expect(resultado.pluck(:id)).to include('10.04')
    end
  end

  it 'keeps the general account exactly as before, with the switch on' do
    geral = conta('geral')
    antes = with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) { leitura_de(geral).capitulos }
    leitura = with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') { leitura_de(geral).tap(&:artigos) }

    expect(leitura.capitulos).to eq(antes)
    expect(leitura.artigo('10.04')).to be_a(Article)
    expect(leitura.artigo('10.04').content).to eq('Texto do artigo base.')
  end

  it 'keeps the brokerage on the general article with the switch off' do
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      expect(leitura_de(conta('seguros', 'corretora')).artigo('10.04').title).to eq('Ganhar, perder, reabrir e arquivar')
    end
  end

  it 'falls back to the general article, without error, when the pack has no file' do
    Dir.mktmpdir do |vazia|
      stub_const("#{described_class}::PASTA", Pathname(vazia))

      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        expect(leitura_de(conta('seguros', 'corretora')).artigo('10.04').title).to eq('Ganhar, perder, reabrir e arquivar')
      end
    end
  end

  it 'refuses a variant section that the base article does not have' do
    base = "---\nid: \"10.04\"\ntitulo: \"Base\"\n---\n\n## O que é\n\nTexto.\n"
    variante = "---\nid: \"10.04\"\n---\n\n## Outra seção\n\nTexto.\n"

    expect { described_class.sobrepor(base, variante, 'teste.md') }
      .to raise_error(Autonomia::CentralDeAjuda::ArtigoFonte::FormatoInvalido, /Outra seção/)
  end

  it 'refuses a variant with another id' do
    base = "---\nid: \"10.04\"\ntitulo: \"Base\"\n---\n\n## O que é\n\nTexto.\n"
    variante = "---\nid: \"10.05\"\n---\n\n## O que é\n\nOutro.\n"

    expect { described_class.sobrepor(base, variante, 'teste.md') }
      .to raise_error(Autonomia::CentralDeAjuda::ArtigoFonte::FormatoInvalido, /id diferente/)
  end
end
