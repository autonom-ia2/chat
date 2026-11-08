require 'rails_helper'

# #1431 (F1, PR 1b) — a tabela do PDF lida pela posição das células: cada fileira vira um item com o cabeçalho da coluna
# de cada valor. Linhas montadas à mão, como o PdfParagrafos as entrega (y, letra, fonte, direita, texto e os trechos com a posição).
RSpec.describe Autonomia::Agents::Knowledge::Processors::PdfTabelas do
  def celula(texto, esquerda, fim, fonte = 'F1')
    { x: esquerda, fim: fim, texto: texto, fonte: fonte }
  end

  def linha(altura, *celulas)
    { y: altura, letra: 10.0, fonte: celulas.to_set { |c| c[:fonte] }, direita: celulas.pluck(:fim).max,
      texto: celulas.pluck(:texto).join(' '), trechos: celulas }
  end

  def corrida(altura, texto, fim = 540)
    linha(altura, celula(texto, 54, fim))
  end

  def pagina(linhas)
    { linhas: linhas, normal: 12.0, fonte_do_corpo: 'F1', letra_do_corpo: 10.0, corpo: linhas }
  end

  # Prazo curto em dois planos lado a lado: o cabeçalho do plano cobre duas colunas, o da coluna fica sobre ela, e a
  # linha "Dias Premio Dias Premio" veio juntada pelo leitor numa célula só, por cima das quatro colunas.
  let(:prazo_curto) do
    [corrida(700, 'O premio retido no cancelamento segue a tabela de prazo curto abaixo, conforme o plano contratado.'),
     linha(670, celula('PLANO ANUAL', 50, 120, 'F2'), celula('PLANO BIANUAL', 250, 330, 'F2')),
     linha(657, celula('Qtd', 55, 75, 'F2'), celula('% do', 150, 175, 'F2'), celula('Qtd', 255, 275, 'F2'),
           celula('% do', 350, 375, 'F2')),
     linha(644, celula('Dias Premio Dias Premio', 50, 390, 'F2')),
     linha(624, celula('1 a 15', 50, 80), celula('13%', 150, 170), celula('1 a 30', 250, 280), celula('13%', 350, 370)),
     linha(604, celula('16 a 30', 50, 85), celula('20%', 150, 170), celula('31 a 60', 250, 285), celula('20%', 350, 370)),
     linha(584, celula('31 a 45', 50, 85), celula('27%', 150, 170), celula('61 a 90', 250, 285), celula('27%', 350, 370)),
     corrida(560, 'Para os prazos nao previstos na tabela vale o percentual do prazo imediatamente inferior a ele.')]
  end

  let(:leitor) do
    Class.new do
      include Autonomia::Agents::Knowledge::Processors::PdfParagrafos
      include Autonomia::Agents::Knowledge::Processors::PdfBlocos
      include Autonomia::Agents::Knowledge::Processors::PdfTabelas
      public :faixas_de_tabela, :bloco_da_tabela, :itens_do_grupo
    end.new
  end

  # Invalidez: sem negrito, o cabeçalho são só as linhas curtas logo acima da tabela; a célula que quebra em duas linhas
  # e o valor dela, um pouco abaixo, são uma fileira só.
  let(:invalidez) do
    [corrida(720, 'O seguro paga a invalidez permanente por acidente pelo percentual da tabela abaixo sobre o capital.'),
     linha(690, celula('% SOBRE', 470, 520)),
     linha(684, celula('Invalidez', 70, 115)),
     linha(678, celula('Discriminacao', 250, 320), celula('CAPITAL', 470, 515)),
     linha(660, celula('PARCIAL', 70, 112), celula('Surdez total incuravel de um dos ouvidos', 130, 310), celula('20', 490, 500)),
     linha(640, celula('Mudez incuravel', 130, 200), celula('50', 490, 500)),
     linha(620, celula('Perda total da visao de um olho, quando ja nao tiver a outra', 130, 450)),
     linha(615, celula('70', 490, 500)),
     linha(609, celula('vista', 130, 150)),
     linha(590, celula('Surdez total incuravel de ambos os ouvidos', 130, 320), celula('40', 490, 500))]
  end

  it 'finds the table between the paragraphs, with the bold header rows inside it' do
    expect(leitor.faixas_de_tabela(pagina(prazo_curto))).to eq([[1, 1, 6]])
  end

  it 'gives every row the header of each column, the plan over its two columns and the merged line split by word' do
    linhas = prazo_curto
    bloco = leitor.bloco_da_tabela({ cabecalho: [], linhas: linhas[1..6] }, pagina(linhas), 31)

    expect(bloco[:itens]).to eq(
      ['PLANO ANUAL Qtd Dias: 1 a 15 | % do Premio: 13% | PLANO BIANUAL Qtd Dias: 1 a 30 | % do Premio: 13%',
       'PLANO ANUAL Qtd Dias: 16 a 30 | % do Premio: 20% | PLANO BIANUAL Qtd Dias: 31 a 60 | % do Premio: 20%',
       'PLANO ANUAL Qtd Dias: 31 a 45 | % do Premio: 27% | PLANO BIANUAL Qtd Dias: 61 a 90 | % do Premio: 27%']
    )
  end

  it 'gives the section text as the labeled rows, one per line' do
    linhas = prazo_curto
    bloco = leitor.bloco_da_tabela({ cabecalho: [], linhas: linhas[1..6] }, pagina(linhas), 31)

    expect(bloco).to include(tipo: :tabela, pagina: 31, texto: bloco[:itens].join("\n"))
  end

  it 'takes the short lines right above the table as header' do
    expect(leitor.faixas_de_tabela(pagina(invalidez))).to eq([[1, 3, 9]])
  end

  it 'reads the header from the short lines above when it has no bold, and a cell broken in two lines as one' do
    linhas = invalidez
    bloco = leitor.bloco_da_tabela({ cabecalho: linhas[1..2], linhas: linhas[3..9] }, pagina(linhas), 60)

    expect(bloco[:itens]).to eq(
      ['Discriminacao | % SOBRE: CAPITAL',
       'Invalidez: PARCIAL | Surdez total incuravel de um dos ouvidos | % SOBRE: 20',
       'Mudez incuravel | % SOBRE: 50',
       'Perda total da visao de um olho, quando ja nao tiver a outra vista | % SOBRE: 70',
       'Surdez total incuravel de ambos os ouvidos | % SOBRE: 40']
    )
  end

  it 'stops the header above the table at a caption wider than half the body' do
    linhas = [corrida(720, 'Texto do contrato que vai ate a margem direita da pagina, como todo paragrafo.'),
              linha(700, celula('TABELA PARA CALCULO DE PERCENTUAIS DE CAPITAL SEGURADO', 150, 430)),
              *invalidez.drop(1)].each_with_index.map { |uma, indice| uma.merge(y: 720 - (indice * 6)) }

    expect(leitor.faixas_de_tabela(pagina(linhas)).first.first).to eq(2)
  end

  it 'does not read a justified paragraph as a table: a wide word space is not a cell gap' do
    linhas = (0..4).map { |n| linha(700 - (n * 12), celula('palavras do texto', 54, 300), celula('justificado', 310, 540)) }

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([])
  end

  it 'does not read numbered clauses or a marked list running to the margin as a table' do
    linhas = %w[5.1.5. 5.1.6. 5.1.7. 5.1.8.].each_with_index.map do |numero, indice|
      linha(700 - (indice * 12), celula(numero, 54, 80), celula('Texto da clausula que segue ate a margem direita', 120, 540))
    end

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([])
  end

  it 'leaves the last short line of the introduction paragraph out of the header' do
    linhas = [corrida(700, 'O premio retido no cancelamento segue a tabela abaixo, conforme o plano que foi contratado'),
              corrida(688, 'pelo segurado:', 200),
              *[['1 a 15', '13%'], ['16 a 30', '20%'], ['31 a 45', '27%']].each_with_index.map do |(prazo, taxa), indice|
                linha(676 - (indice * 20), celula(prazo, 50, 85), celula(taxa, 150, 170), celula('anual', 250, 280))
              end]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([[2, 2, 4]])
  end

  it 'leaves a short bold title right above the table out of the header' do
    linhas = [linha(698, celula('Tabela 2 - Prazos', 60, 150, 'F2')),
              *[['1 a 15', '13%'], ['16 a 30', '20%'], ['31 a 45', '27%']].each_with_index.map do |(prazo, taxa), indice|
                linha(686 - (indice * 20), celula(prazo, 50, 85), celula(taxa, 150, 170), celula('anual', 250, 280))
              end,
              corrida(600, 'Texto do contrato que vai ate a margem direita da pagina, como todo paragrafo.')]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([[1, 1, 3]])
  end

  it 'gives a cell the title of its own column, even when the row has an empty column' do
    linhas = [linha(680, celula('Prazo', 50, 80, 'F2'), celula('% do premio', 150, 200, 'F2'), celula('Obs', 300, 330, 'F2')),
              linha(660, celula('1 a 15', 50, 80), celula('13%', 150, 170), celula('sem carencia', 300, 360)),
              linha(640, celula('16 a 30', 50, 85), celula('carencia de 3 dias', 300, 380))]
    bloco = leitor.bloco_da_tabela({ cabecalho: [], linhas: linhas }, pagina(linhas), 1)

    expect(bloco[:itens].last).to eq('Prazo: 16 a 30 | Obs: carencia de 3 dias')
  end

  it 'keeps a left aligned paragraph as one item, and splits a justified list where a line stops before the margin' do
    soltas = (0..5).map { |indice| corrida(700 - (indice * 12), "linha de texto alinhado a esquerda #{indice}", 300 + (indice * 30)) }
    lista = [corrida(600, 'a) Quaisquer bens ou acessorios instalados no veiculo, mesmo em decorrencia'),
             corrida(588, 'de sinistro coberto;', 200), corrida(576, 'b) Custos relativos a blindagem do veiculo segurado, salvo'),
             corrida(564, 'contratacao especifica;', 220)]
    folha = pagina([*soltas, *lista])

    expect([leitor.itens_do_grupo(soltas, folha).size, leitor.itens_do_grupo(lista, folha).size]).to eq([1, 2])
  end

  it 'needs three lines of two or more cells to be a table' do
    linhas = [corrida(700, 'Texto.'), linha(680, celula('5.1.5.', 54, 80), celula('Restabelecido o pagamento', 120, 540)),
              linha(668, celula('5.1.6.', 54, 80), celula('Cancelado o seguro', 120, 540)), corrida(656, 'Fim.')]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([])
  end

  # Duas células por linha sem cabeçalho em destaque: o marcador e o texto (na letra 9 a folga passa de GAP_DE_CELULA),
  # ou o número da cláusula curta e o texto. Sem título de coluna, ler isso como tabela não acrescenta nada.
  it 'does not read a marked list in a small letter as a table' do
    lista = %w[Guincho Chaveiro Pneu Taxi].each_with_index.map do |texto, indice|
      linha(700 - (indice * 12), celula('•', 18, 22.5), celula("#{texto} ate o limite do plano;", 37, 200)).merge(letra: 9.0)
    end

    expect(leitor.faixas_de_tabela(pagina([*lista, corrida(640, 'Texto do contrato que vai ate a margem direita.')]))).to eq([])
  end

  it 'does not read short numbered clauses as a table' do
    linhas = %w[5.2.1. 5.2.2. 5.2.3.].each_with_index.map do |numero, indice|
      linha(700 - (indice * 12), celula(numero, 18, 40), celula('Incendio;', 63, 110))
    end

    expect(leitor.faixas_de_tabela(pagina([*linhas, corrida(650, 'Texto do contrato que vai ate a margem direita.')]))).to eq([])
  end

  it 'does not take a short introduction line above a two cell list as its header' do
    lista = %w[Guincho Chaveiro Pneu].each_with_index.map do |texto, indice|
      linha(664 - (indice * 12), celula('•', 18, 22.5), celula("#{texto} ate o limite do plano;", 37, 200)).merge(letra: 9.0)
    end
    linhas = [corrida(706, 'Texto do contrato que vai ate a margem direita.'), linha(676, celula('Estao cobertos:', 54, 120)), *lista]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([])
  end

  it 'reads two columns as a table when the short lines above head both columns' do
    linhas = [corrida(720, 'Texto do contrato que vai ate a margem direita.'), linha(690, celula('Prazo', 55, 80)),
              linha(684, celula('% do premio retido', 140, 220)),
              *[['1 a 15', '13%'], ['16 a 30', '20%'], ['31 a 45', '27%']].each_with_index.map do |(prazo, taxa), indice|
                linha(670 - (indice * 20), celula(prazo, 50, 85), celula(taxa, 170, 190))
              end]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([[1, 3, 5]])
  end

  it 'reads two columns as a table when the first row stands out in bold' do
    linhas = [linha(680, celula('Idade', 50, 80, 'F2'), celula('Depreciacao', 150, 210, 'F2')),
              linha(660, celula('Ate 1 ano', 50, 95), celula('10%', 150, 170)),
              linha(640, celula('Ate 3 anos', 50, 100), celula('40%', 150, 170)),
              corrida(610, 'Texto do contrato que vai ate a margem direita.')]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([[0, 0, 2]])
  end
end
