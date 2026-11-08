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
      public :faixas_de_tabela, :bloco_da_tabela
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
      ['Invalidez: Discriminacao | % SOBRE: CAPITAL',
       'Invalidez: PARCIAL | Surdez total incuravel de um dos ouvidos | % SOBRE: 20',
       'Invalidez: Mudez incuravel | % SOBRE: 50',
       'Invalidez: Perda total da visao de um olho, quando ja nao tiver a outra vista | % SOBRE: 70',
       'Invalidez: Surdez total incuravel de ambos os ouvidos | % SOBRE: 40']
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

  it 'needs three lines of two or more cells to be a table' do
    linhas = [corrida(700, 'Texto.'), linha(680, celula('5.1.5.', 54, 80), celula('Restabelecido o pagamento', 120, 540)),
              linha(668, celula('5.1.6.', 54, 80), celula('Cancelado o seguro', 120, 540)), corrida(656, 'Fim.')]

    expect(leitor.faixas_de_tabela(pagina(linhas))).to eq([])
  end
end
