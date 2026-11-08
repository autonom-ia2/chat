require 'rails_helper'

# #1431 (F1) — o corte por seção: os blocos que o formato entrega (título com nível, parágrafo, página) viram trechos de
# uma seção só, cada um começando pelo caminho (Documento › Seção › Subseção), com as páginas de onde veio.
RSpec.describe Autonomia::Agents::Knowledge::CortePorSecao do
  def titulo(texto, nivel, pagina = 1)
    { tipo: :titulo, nivel: nivel, texto: texto, pagina: pagina }
  end

  def paragrafo(texto, pagina = 1)
    { tipo: :paragrafo, texto: texto, pagina: pagina }
  end

  def cortar(blocos, **opcoes)
    described_class.new(blocos, documento: 'Condicoes Gerais', **opcoes).trechos
  end

  let(:franquia) { 'A franquia e o valor que o segurado paga em cada sinistro de dano parcial ao veiculo segurado.' * 3 }
  let(:reducao) { 'Quem contrata a franquia reduzida paga menos no sinistro e um premio maior na contratacao do seguro.' }

  it 'starts every piece with the path of titles and keeps one section per piece', :aggregate_failures do
    trechos = cortar([titulo('3. COBERTURAS', 1), titulo('3.1 Franquia', 2), paragrafo(franquia),
                      titulo('3.2 Guincho', 2), paragrafo('O guincho atende ate 200 km do local do evento, em todo o pais. ' * 4)])

    expect(trechos.size).to eq(2)
    expect(trechos.first[:text]).to eq("Condicoes Gerais › 3. COBERTURAS › 3.1 Franquia\n\n#{franquia}")
    expect(trechos.last[:text]).to start_with('Condicoes Gerais › 3. COBERTURAS › 3.2 Guincho')
    expect(trechos.first[:metadata]).to include(caminho: ['Condicoes Gerais', '3. COBERTURAS', '3.1 Franquia'],
                                                section_heading: '3.1 Franquia')
    expect(trechos.map { |trecho| trecho[:metadata][:secao_id] }.uniq.size).to eq(2)
  end

  it 'closes a subsection when a title of the same or a higher level comes' do
    trechos = cortar([titulo('3. COBERTURAS', 1), titulo('3.1 Franquia', 2), paragrafo(franquia),
                      titulo('4. EXCLUSOES', 1), paragrafo('Nao ha cobertura para o veiculo usado em competicao de qualquer tipo.')])

    expect(trechos.last[:text]).to start_with("Condicoes Gerais › 4. EXCLUSOES\n\n")
  end

  it 'keeps the pages the piece came from' do
    trechos = cortar([titulo('3.1 Franquia', 1, 4), paragrafo(franquia, 4), paragrafo(reducao, 5)])

    expect(trechos.first[:paginas]).to eq([4, 5])
  end

  it 'joins a section below the floor with the next sibling, so a two-line definition is not a piece alone' do
    trechos = cortar([titulo('Definicoes', 1), titulo('Avaria', 2), paragrafo('Dano ao veiculo.'),
                      titulo('Franquia', 2), paragrafo(franquia)])

    expect(trechos.size).to eq(1)
    expect(trechos.first[:text]).to include("Avaria\nDano ao veiculo.", franquia)
  end

  it 'splits a long section by paragraph, repeating the last paragraph at the start of the next piece', :aggregate_failures do
    paragrafos = (1..6).map { |n| paragrafo("Paragrafo #{n}: #{'regra da cobertura do seguro ' * 10}") }
    trechos = cortar([titulo('Regras', 1), *paragrafos], maximo: 700)

    expect(trechos.size).to be > 1
    expect(trechos).to all(satisfy { |trecho| trecho[:text].start_with?('Condicoes Gerais › Regras') })
    ultimo_do_primeiro = trechos.first[:text].split("\n\n").last
    expect(trechos.second[:text].split("\n\n")[1]).to eq(ultimo_do_primeiro)
  end

  it 'never cuts a paragraph longer than the maximum in the middle of a word' do
    longo = "#{'O segurado deve avisar a seguradora logo que souber do sinistro. ' * 30}Fim."
    trechos = cortar([titulo('Aviso', 1), paragrafo(longo)], maximo: 600)

    corpo = trechos.map { |trecho| trecho[:text].delete_prefix("Condicoes Gerais › Aviso\n\n") }
    expect(corpo).to all(satisfy { |texto| texto.length <= 600 && longo.include?(texto) })
  end

  it 'puts the text before the first title under the document name' do
    trechos = cortar([paragrafo('Bem-vindo ao seguro. Leia com atencao todas as condicoes deste contrato.'),
                      titulo('1. OBJETIVO', 1), paragrafo(franquia)])

    expect(trechos.first[:text]).to start_with("Condicoes Gerais\n\nBem-vindo")
  end

  it 'gives the metadata the Ingestor and the Retriever read', :aggregate_failures do
    metadata = cortar([titulo('3.1 Franquia', 1), paragrafo(franquia)]).first[:metadata]

    expect(metadata).to include(material_type: 'secao', char_span: a_value > 0)
    expect(metadata[:keywords]).to include('franquia')
  end

  it 'never drops a title with nothing under it: a short bold list item read as a title keeps its text', :aggregate_failures do
    trechos = cortar([titulo('5. EXCLUSOES', 1), titulo('j) Perdas durante competicoes de qualquer tipo', 2),
                      titulo('k) Acidentes por dirigir sem habilitacao', 2), titulo('6. ACEITACAO', 1), paragrafo(franquia)])
    texto = trechos.pluck(:text).join("\n")

    expect(texto).to include('j) Perdas durante competicoes de qualquer tipo', 'k) Acidentes por dirigir sem habilitacao')
    expect(trechos.last[:text]).to start_with('Condicoes Gerais › 6. ACEITACAO')
  end

  it 'returns nothing for no blocks' do
    expect(cortar([])).to eq([])
  end
end
