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
    trechos = cortar([titulo('Regras', 1), *paragrafos], maximo: 700).select { |trecho| trecho[:metadata][:material_type] == 'secao' }

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

  it 'keeps the last page of a paragraph that goes on to the next page' do
    trechos = cortar([titulo('3.1 Franquia', 1, 4), paragrafo(franquia, 4).merge(pagina_fim: 6)])

    expect(trechos.first[:paginas]).to eq([4, 6])
  end

  it 'joins a small section only once, so its text never ends under a section two places ahead', :aggregate_failures do
    trechos = cortar([titulo('Definicoes', 1), titulo('Avaria', 2), paragrafo('Dano ao veiculo.'),
                      titulo('Bonus', 2), paragrafo('Desconto na renovacao.'), titulo('Franquia', 2), paragrafo(franquia)])

    avaria = trechos.find { |trecho| trecho[:text].include?('Dano ao veiculo.') }
    expect(avaria[:text]).to start_with('Condicoes Gerais › Definicoes › Bonus')
    expect(trechos.last[:text]).to start_with('Condicoes Gerais › Definicoes › Franquia')
    expect(trechos.last[:text]).not_to include('Dano ao veiculo.')
  end

  it 'keeps a small last section with no sibling after it' do
    trechos = cortar([titulo('Coberturas', 1), paragrafo(franquia), titulo('Ouvidoria', 1), paragrafo('Ligue 0800.')])

    expect(trechos.last[:text]).to eq("Condicoes Gerais › Ouvidoria\n\nLigue 0800.")
  end

  it 'does not join a small section into its own subsection' do
    trechos = cortar([titulo('Assistencia', 1), paragrafo('Servicos 24 horas.'), titulo('Guincho', 2), paragrafo(franquia)])

    expect(trechos.first[:text]).to eq("Condicoes Gerais › Assistencia\n\nServicos 24 horas.")
  end

  it 'loses no paragraph: every block text is in some piece' do
    blocos = [paragrafo('Abertura do contrato.'), titulo('A', 1), paragrafo('Curto.'), titulo('B', 1), paragrafo(franquia),
              titulo('B.1', 2), titulo('B.2', 2), paragrafo(reducao * 20), titulo('C', 1)]
    texto = cortar(blocos, maximo: 500).pluck(:text).join("\n")

    expect(blocos.pluck(:texto).flat_map(&:split).uniq - texto.split).to be_empty
  end

  it 'returns nothing for no blocks' do
    expect(cortar([])).to eq([])
  end

  # PR 1b: na seção longa, o item de lista, o verbete do glossário e a fileira da tabela também viram trecho próprio,
  # para não sumirem diluídos no trecho da seção inteira.
  context 'with items in a long section' do
    let(:abertura) { 'Alem das exclusoes gerais, estarao excluidas da cobertura do seguro:' }
    let(:itens) do
      [abertura, 'a) Quaisquer bens ou acessorios instalados no veiculo, mesmo em decorrencia de sinistro coberto;',
       *('b'..'k').map { |letra| "#{letra}) Perdas ou danos por desgaste, uso ou falha de material do veiculo segurado;" }]
    end
    let(:exclusoes) { { tipo: :paragrafo, texto: itens.join("\n"), itens: itens, pagina: 7 } }

    it 'keeps the section piece and adds one piece per item, with the opening line that introduces the list', :aggregate_failures do
      trechos = cortar([titulo('2. EXCLUSOES', 1, 7), exclusoes])
      de_item = trechos.select { |trecho| trecho[:metadata][:material_type] == 'item' }

      expect(trechos.first[:metadata][:material_type]).to eq('secao')
      expect(de_item.size).to eq(11)
      expect(de_item.first[:text]).to eq("2. EXCLUSOES\n\n#{abertura}\n#{itens[1]}")
      expect(de_item.first[:metadata]).to include(caminho: ['Condicoes Gerais', '2. EXCLUSOES'],
                                                  secao_id: trechos.first[:metadata][:secao_id])
      expect(de_item.first[:paginas]).to eq([7, 7])
    end

    it 'joins a short item to the next one, so a glossary term stays with its definition' do
      verbetes = ['Perda Parcial', "Dano ao veiculo menor que 75% do valor determinado. #{('Texto da definicao. ' * 8).strip}",
                  'Premio', "Valor pago pelo segurado para a seguradora assumir o risco. #{('Texto da definicao. ' * 8).strip}",
                  'Sinistro', "Ocorrencia do evento coberto pelo seguro durante a vigencia. #{('Texto da definicao. ' * 8).strip}"]
      glossario = { tipo: :paragrafo, texto: verbetes.join("\n"), itens: verbetes, pagina: 3 }

      de_item = cortar([titulo('3. DEFINICOES', 1, 3), glossario]).select { |trecho| trecho[:metadata][:material_type] == 'item' }

      expect(de_item.map { |trecho| trecho[:text].split("\n\n", 2).last }).to eq(verbetes.each_slice(2).map { |par| par.join("\n") })
    end

    it 'gives an item crossing two pieces of its section no pointer, so the search keeps the whole item' do
      longo = "a) #{'O segurado perde o direito se agravar o risco de proposito. ' * 12}".strip
      blocos = [titulo('2. PERDA DE DIREITOS', 1, 7),
                { tipo: :paragrafo, texto: [abertura, longo, itens[2]].join("\n"), itens: [abertura, longo, itens[2]], pagina: 7 }]
      de_item = cortar(blocos, maximo: 500).select { |trecho| trecho[:metadata][:material_type] == 'item' }

      expect(de_item.map { |trecho| trecho[:metadata].key?(:trecho_da_secao) }).to include(false)
    end

    it 'gives no item pieces to a short section' do
      curta = { tipo: :paragrafo, texto: itens.first(3).join("\n"), itens: itens.first(3), pagina: 7 }

      expect(cortar([titulo('2. EXCLUSOES', 1), curta]).pluck(:metadata).pluck(:material_type)).to eq(['secao'])
    end
  end

  context 'with a table' do
    let(:fileiras) { (1..40).map { |n| "PLANO ANUAL Dias: #{n * 15} a #{(n * 15) + 14} | % do premio: #{n + 10}%" } }
    let(:tabela) { { tipo: :tabela, texto: fileiras.join("\n"), itens: fileiras, pagina: 31 } }

    it 'splits a long table between whole rows, each one with the header of its columns', :aggregate_failures do
      de_secao = cortar([titulo('5.1 Prazo curto', 1, 31), tabela], maximo: 300)
                 .select { |trecho| trecho[:metadata][:material_type] == 'secao' }

      expect(de_secao.size).to be > 1
      corpos = de_secao.map { |trecho| trecho[:text].split("\n\n", 2).last }
      expect(corpos).to all(satisfy { |corpo| corpo.length <= 300 })
      expect(corpos.flat_map { |corpo| corpo.lines(chomp: true) }).to eq(fileiras)
    end

    it 'gives one piece per row, with the header of each column' do
      de_item = cortar([titulo('5.1 Prazo curto', 1, 31), tabela]).select { |trecho| trecho[:metadata][:material_type] == 'item' }

      expect(de_item.map { |trecho| trecho[:text].split("\n\n", 2).last }).to eq(tabela[:itens])
    end

    it 'points every item to the piece of its section that holds it' do
      trechos = cortar([titulo('5.1 Prazo curto', 1, 31), tabela], maximo: 300)

      expect(trechos.select { |trecho| trecho[:metadata][:material_type] == 'item' }).to all(
        satisfy { |item| trechos[item[:metadata][:trecho_da_secao]][:text].include?(item[:text].split("\n\n", 2).last) }
      )
    end
  end
end
