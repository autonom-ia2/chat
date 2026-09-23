require 'rails_helper'

RSpec.describe Autonomia::CentralDeAjuda::ArtigoFonte do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:titulos) { { '02.03' => 'Seu e-mail e a senha', '02.04' => 'Sua assinatura', '02.06' => 'Sua disponibilidade' } }
  let(:corpo) do
    <<~MD
      ## O que é

      A disponibilidade diz se você recebe conversas.
      Ela vale por conta.

      ## Por que importa

      Veja o [02.04] antes.

      ## Como faz

      ![PRINT 02.06-a: Menu da foto](prints/02.06-a.png)

      1. Abra o menu.

      ## O que dá errado

      - **"Sumiu."** Confira.

      ## Veja também

      - [02.04] Sua assinatura
      - [02.03] Seu e-mail e a senha

      <!-- PRINT 02.06-a
      rota: profile_settings_index
      -->
    MD
  end
  let(:texto) do
    <<~MD
      ---
      id: "02.06"
      titulo: "Sua disponibilidade"
      capitulo: "02"
      publico: ambos
      prioridade: P1
      me_leve_ate_la:
        rota: profile_settings_index
        destaque: null
      requer: null
      assuntos: ["01.2-definir-disponibilidade"]
      conferido_em: "2026-09-22"
      evidencias:
        - app/models/user.rb:1
      ---
      #{corpo}
    MD
  end
  let(:caminho) { dir.join('02.06-sua-disponibilidade.md').tap { |p| File.write(p, texto) } }

  after { FileUtils.remove_entry(dir) }

  def fonte = described_class.new(caminho.to_s, titulos: titulos)

  it 'lê o cabeçalho e monta o slug com o prefixo da plataforma' do
    expect(fonte.id).to eq('02.06')
    expect(fonte.capitulo).to eq('02')
    expect(fonte.titulo).to eq('Sua disponibilidade')
    expect(fonte.slug).to eq('plataforma-02-06')
  end

  it 'troca o número do artigo pelo título, com link, sem repetir o título no Veja também' do
    expect(fonte.conteudo).to include('Veja o [Sua assinatura](plataforma-02-04) antes.')
    expect(fonte.conteudo).to include("- [Sua assinatura](plataforma-02-04)\n")
    expect(fonte.conteudo).to include('- [Seu e-mail e a senha](plataforma-02-03)')
    expect(fonte.conteudo).not_to include('[02.0')
  end

  it 'tira comentários e o print que ainda não existe' do
    expect(fonte.conteudo).not_to include('<!--')
    expect(fonte.conteudo).not_to include('rota: profile_settings_index')
    expect(fonte.conteudo).not_to include('PRINT')
    expect(fonte.conteudo).to start_with('## O que é')
  end

  it 'publica o print que existe, na pasta pública e com a legenda como texto alternativo' do
    prints = dir.join('prints')
    FileUtils.mkdir_p(prints)
    File.write(prints.join('02.06-a.png'), 'png')
    stub_const("#{described_class}::PASTA_PRINTS", prints)

    expect(fonte.conteudo).to include('![Menu da foto](/central-de-ajuda/prints/02.06-a.png)')
  end

  it 'recusa print sem legenda, para o leitor de tela não ler só o código do print' do
    prints = dir.join('prints')
    FileUtils.mkdir_p(prints)
    File.write(prints.join('02.06-a.png'), 'png')
    stub_const("#{described_class}::PASTA_PRINTS", prints)
    File.write(caminho, texto.sub('![PRINT 02.06-a: Menu da foto]', '![PRINT 02.06-a]'))

    expect { fonte.conteudo }.to raise_error(described_class::FormatoInvalido, a_string_including('print sem legenda'))
  end

  it 'usa o primeiro parágrafo de "O que é" como descrição' do
    expect(fonte.descricao).to eq('A disponibilidade diz se você recebe conversas. Ela vale por conta.')
  end

  it 'tira negrito, código e link da descrição' do
    File.write(caminho, texto.sub('A disponibilidade diz se você recebe conversas.',
                                  'A **disponibilidade** do `status` segue o [02.04].'))

    expect(fonte.descricao).to eq('A disponibilidade do status segue o Sua assinatura. Ela vale por conta.')
  end

  it 'guarda em meta os campos do cabeçalho que a tela de leitura usa, com o sha' do
    expect(fonte.meta).to include(
      'id' => '02.06', 'publico' => 'ambos', 'requer' => nil,
      'me_leve_ate_la' => { 'rota' => 'profile_settings_index', 'destaque' => nil }
    )
    expect(fonte.meta['sha']).to eq(fonte.sha)
    expect(fonte.meta).not_to have_key('evidencias')
  end

  it 'muda o sha quando o texto muda' do
    antes = fonte.sha
    File.write(caminho, texto.sub('Ela vale por conta.', 'Ela vale em cada conta.'))

    expect(fonte.sha).not_to eq(antes)
  end

  it 'recusa link para artigo que não existe no mapa' do
    File.write(caminho, texto.sub('[02.04] antes', '[09.99] antes'))

    expect { fonte.conteudo }.to raise_error(described_class::FormatoInvalido, a_string_including('09.99'))
  end

  it 'recusa arquivo sem cabeçalho' do
    File.write(caminho, corpo)

    expect { fonte }.to raise_error(described_class::FormatoInvalido, a_string_including('sem cabeçalho'))
  end

  it 'não mexe em link Markdown que já existe' do
    File.write(caminho, texto.sub('Veja o [02.04] antes.', 'Veja o [02.04](https://exemplo.com) antes.'))

    expect(fonte.conteudo).to include('[02.04](https://exemplo.com)')
  end

  describe 'os artigos reais do repositório' do
    let(:mapa) { JSON.parse(Rails.root.join('docs/central-de-ajuda/mapa-de-artigos.json').read) }
    let(:titulos_reais) { mapa['capitulos'].flat_map { |c| c['artigos'].map { |a| [a['id'], a['titulo']] } }.to_h }

    it 'abrem, têm link só para artigos do mapa e seguem o mapa no título' do
      arquivos = Dir[Rails.root.join('lib/central_de_ajuda/*/*.md')]
      expect(arquivos).not_to be_empty

      arquivos.each do |arquivo|
        f = described_class.new(arquivo, titulos: titulos_reais)
        expect(f.conteudo).to be_present, arquivo
        expect(f.titulo).to eq(titulos_reais[f.id]), arquivo
        expect(File.basename(arquivo)).to start_with("#{f.id}-")
      end
    end
  end
end
