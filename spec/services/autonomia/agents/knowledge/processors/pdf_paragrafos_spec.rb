require 'rails_helper'

# #1426 (#2425) — o texto do PDF da base de conhecimento sai em parágrafos pela posição das linhas na página, não pela grade
# do `page.text` (que punha linha em branco no meio do parágrafo e fazia o Chunker cortar a frase). PDF de verdade, montado
# em memória, com texto posicionado como num "Print To PDF": linhas a 13,2 pt, parágrafos a 26,4 pt, rodapé no pé.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  let(:account) { create(:account) }
  let(:bia) { instance_double(Autonomia::Agents::Agent, instrucao_mantida?: false, config: {}) }
  let(:file) { double('attachment', attached?: true, download: pdf) } # rubocop:disable RSpec/VerifiedDoubles
  let(:source) { material(bia) }
  let(:linha) { 13.2 }
  let(:topo) { 780 }
  let(:pdf) { pdf_com([pagina(sumario, 1), pagina(definicoes, 2), pagina(definicoes, 3), pagina(definicoes, 4)]) }

  def material(agente)
    double('source', reference: 'cg.pdf', source_type: 'pdf', file: file, account: account, agent: agente).tap do |fonte| # rubocop:disable RSpec/VerifiedDoubles
      allow(fonte).to receive(:paginas_de_fora=)
      allow(fonte).to receive(:secoes=)
    end
  end

  def extrair(fonte = source)
    described_class.new(fonte).extract
  end

  # Uma página: [texto, y] de cada linha do corpo, mais o pé (número da página e rodapé corrido), separado do corpo.
  def pagina(linhas, numero)
    [*linhas, [numero.to_s, 25.9], ['Versao SETEMBRO-2026', 15.6]]
  end

  # Linhas seguidas a partir de `inicio`; nil deixa uma linha em branco (o espaço de parágrafo).
  def corpo(*textos, inicio: topo)
    textos.each_with_index.filter_map { |texto, indice| [texto, inicio - (indice * linha)] if texto }
  end

  def definicoes
    corpo('Dano Moral', 'Ofensa aos principios e valores de ordem moral, tais como honra e dignidade',
          'pessoal ou familiar. Cabe ao juiz do processo fixar o valor da reparacao.', nil,
          'Dano Material', 'Dano causado exclusivamente a propriedade material de pessoas.')
  end

  def sumario
    corpo('Sumario', nil, "1. OBJETIVO DO SEGURO#{'.' * 60}4", "2. COBERTURAS#{'.' * 60}5")
  end

  # PDF mínimo com Helvetica: cada linha é um "Td" na altura dada (e na margem esquerda dada; padrão 54). O quarto item,
  # quando há, troca o "(texto) Tj" pelo operador cru (ex.: TJ com espaçamento entre letras); o quinto, a linha inteira.
  def pdf_com(paginas)
    ids = paginas.each_index.map { |indice| 5 + (2 * indice) }
    objetos = ['<< /Type /Catalog /Pages 2 0 R >>',
               "<< /Type /Pages /Kids [#{ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{paginas.size} >>",
               '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>']
    paginas.each_with_index do |linhas, indice|
      conteudo = linhas.map do |texto, y, x = 54, cru = nil, inteiro = nil|
        inteiro || "BT /F1 10 Tf #{x} #{y} Td #{cru || "(#{texto}) Tj"} ET"
      end.join("\n")
      objetos << '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> ' \
                 "/Contents #{ids[indice] + 1} 0 R >>"
      objetos << "<< /Length #{conteudo.bytesize} >>\nstream\n#{conteudo}\nendstream"
    end
    montar(objetos)
  end

  def montar(objetos)
    corpo = +"%PDF-1.4\n"
    posicoes = objetos.each_with_index.map { |objeto, i| corpo.bytesize.tap { corpo << "#{i + 1} 0 obj\n#{objeto}\nendobj\n" } }
    linhas = posicoes.map { |posicao| format("%010d 00000 n \n", posicao) }.join
    "#{corpo}xref\n0 #{posicoes.size + 1}\n0000000000 65535 f \n#{linhas}" \
      "trailer\n<< /Size #{posicoes.size + 1} /Root 1 0 R >>\nstartxref\n#{corpo.bytesize}\n%%EOF\n"
  end

  describe 'no material da base, com a Fase 2 desligada (conserto de defeito, vale para toda conta)' do
    it 'junta as linhas do mesmo parágrafo e separa parágrafos pelo espaço entre eles' do
      expect(extrair).to include("Dano Moral\nOfensa aos principios e valores de ordem moral, tais como honra e dignidade\n" \
                                 "pessoal ou familiar. Cabe ao juiz do processo fixar o valor da reparacao.\n\nDano Material\n")
    end

    it 'deixa o rodapé corrido só na primeira página e tira o número da página', :aggregate_failures do
      texto = extrair

      expect(texto.scan('Versao SETEMBRO-2026').size).to eq(1)
      expect(texto.lines.map(&:strip)).not_to include('2', '3', '4')
      expect(texto).to include('2. COBERTURAS')
    end

    it 'linha repetida no corpo de toda página fica em todas' do
      expect([extrair.scan('Dano Moral').size, extrair.scan('Dano Material').size]).to eq([3, 3])
    end

    it 'o Chunker não corta mais a frase no meio: a definição inteira fica num trecho só' do
      chunks = Autonomia::Agents::Knowledge::Chunker.new(extrair, source_type: 'pdf').chunks

      expect(chunks).to include(a_string_including('dignidade pessoal ou familiar. Cabe ao juiz'))
    end
  end

  describe 'a virada de página' do
    # O texto vai até o último quarto da folha (842 pt de altura): a última linha fica perto de y = 100.
    let(:pe_da_folha) { 100 + (7 * linha) }
    let(:cheia) { corpo(*Array.new(8) { |n| "Linha corrida numero #{n} do texto." }, inicio: pe_da_folha) }
    let(:pdf) do
      pdf_com([pagina(cheia, 1), pagina(corpo(*Array.new(7) { 'Texto da pagina dois.' }, 'A frase comeca aqui e', inicio: pe_da_folha), 2),
               pagina(corpo('termina na pagina seguinte.', *Array.new(7) { 'Texto da pagina tres.' }, inicio: pe_da_folha), 3),
               pagina(cheia, 4)])
    end

    it 'continua o parágrafo quando o texto da página chega ao pé da folha' do
      chunks = Autonomia::Agents::Knowledge::Chunker.new(extrair, source_type: 'pdf').chunks

      expect(chunks).to include(a_string_including('A frase comeca aqui e termina na pagina seguinte.'))
    end

    it 'não continua quando a página termina no meio da folha (um item por página)' do
      itens = (1..4).map { |numero| pagina(corpo("Item #{numero}", "Descricao do item #{numero} em uma linha."), numero) }
      allow(file).to receive(:download).and_return(pdf_com(itens))

      expect(extrair).to include("Descricao do item 2 em uma linha.\n\nItem 3")
    end
  end

  describe 'o pé da página com conteúdo (catálogo com o preço no pé)' do
    let(:pdf) do
      pdf_com((1..4).map do |numero|
        [*corpo("Produto #{numero}", "Descricao do produto #{numero}."), ["R$ #{numero}.299,00", 60], [numero.to_s, 25.9]]
      end)
    end

    it 'mantém o preço em toda página e tira só o número da página', :aggregate_failures do
      texto = extrair

      expect((1..4).map { |numero| texto.include?("R$ #{numero}.299,00") }).to all(be(true))
      expect(texto).to include("R$ 2.299,00\n\nProduto 3")
      expect(texto.lines.map(&:strip)).not_to include('1', '2', '3', '4')
    end
  end

  describe 'a linha de conteúdo repetida no pé, acima da faixa do rodapé (preço igual em todo item)' do
    let(:pdf) do
      pdf_com((1..4).map { |numero| [*corpo("Produto #{numero}", 'Descricao do produto.'), ['Preco sob consulta', 600]] })
    end

    it 'fica em toda página' do
      expect(extrair.scan('Preco sob consulta').size).to eq(4)
    end
  end

  describe 'o topo da página' do
    let(:pdf) { pdf_com((1..4).map { |numero| pagina([['CONDICAO GERAL', 810], *definicoes], numero) }) }

    it 'não é mexido: o cabeçalho do topo fica em toda página' do
      expect(extrair.scan('CONDICAO GERAL').size).to eq(4)
    end
  end

  describe 'duas colunas' do
    let(:pdf) do
      esquerda = corpo('Coluna um primeira linha', 'coluna um segunda linha')
      direita = corpo('Coluna dois primeira linha', 'coluna dois segunda linha')
      pdf_com([esquerda + direita.map { |texto, y| [texto, y, 320] }])
    end

    it 'tem as mesmas palavras do page.text (a remontagem não perde nem inventa texto)' do
      original = PDF::Reader.new(StringIO.new(pdf)).pages.first.text

      expect(extrair.split.sort).to eq(original.split.sort)
    end
  end

  describe 'a tabela com o cabeçalho repetido no topo de cada página' do
    let(:tabela) { corpo('Modelo Ano Franquia Premio', 'Uno 2020 1500 900', 'Gol 2021 1800 950', 'Onix 2022 2100 1000') }
    let(:pdf) { pdf_com((1..4).map { |numero| pagina(tabela, numero) }) }

    it 'mantém o cabeçalho em toda página (colado nas linhas, não é cabeçalho corrido)' do
      expect(extrair.scan('Modelo Ano Franquia Premio').size).to eq(4)
    end
  end

  describe 'o título em outra fonte, colado ao texto (sem espaço de parágrafo antes do corpo)' do
    let(:pdf) do
      pdf_com([[['1. OBJETIVO DO SEGURO', topo, 54, '/F2 10 Tf (1. OBJETIVO DO SEGURO) Tj'],
                *corpo('Este seguro garante o veiculo segurado.', 'Vale em todo o territorio.', inicio: topo - linha)]])
    end

    it 'fica num bloco próprio, e o Chunker o reconhece como título' do
      meta = Autonomia::Agents::Knowledge::Chunker.new(extrair, source_type: 'pdf').chunks_with_metadata

      expect(meta).to include(a_hash_including(metadata: a_hash_including(section_heading: '1. OBJETIVO DO SEGURO')))
    end
  end

  describe 'a cláusula em caixa alta de várias linhas, na fonte do texto' do
    let(:pdf) { pdf_com([corpo('O SEGURADO DEVERA COMUNICAR O SINISTRO EM', 'ATE SETE DIAS UTEIS CONTADOS DA DATA', 'DO EVENTO')]) }

    it 'fica num parágrafo só (não vira um título por linha)' do
      expect(extrair).to include("O SEGURADO DEVERA COMUNICAR O SINISTRO EM\nATE SETE DIAS UTEIS CONTADOS DA DATA\nDO EVENTO")
    end
  end

  describe 'o título com as letras um pouco espaçadas' do
    let(:pdf) { pdf_com([[['', topo, 54, '0.5 Tc (COBERTURAS) Tj']]]) }

    it 'fica numa palavra só (folga entre letras abaixo de 10% da letra)' do
      expect(extrair).to include('COBERTURAS')
    end
  end

  describe 'a linha com palavras em negrito no meio do parágrafo' do
    let(:pdf) do
      meio = 'BT /F1 10 Tf 54 766.8 Td (em ) Tj /F2 10 Tf (ATE SETE DIAS UTEIS CONTADOS DA DATA) Tj ET'
      pdf_com([[['O segurado deve comunicar o sinistro a seguradora', topo], ['', topo - linha, 54, nil, meio], ['do evento.', topo - (2 * linha)]]])
    end

    it 'continua o parágrafo (as linhas vão até a margem: não é título)' do
      expect(extrair).to include("seguradora\nem ATE SETE DIAS UTEIS CONTADOS DA DATA\ndo evento.")
    end
  end

  describe 'os números de tabela posicionados sem espaço (folga entre 10% e 20% da letra)' do
    let(:pdf) { pdf_com([[['', topo, 54, '[(1) -180 (2) -180 (3) -180 (4) -180 (5)] TJ']]]) }

    it 'ficam separados' do
      expect(extrair).to include('1 2 3 4 5')
    end
  end

  describe 'a palavra com kerning forte entre duas letras' do
    let(:pdf) { pdf_com([[['', topo, 54, '[(T) 120 (otal)] TJ']]]) }

    it 'fica inteira' do
      expect(extrair).to include('Total')
    end
  end

  describe 'a fonte embutida em subconjunto' do
    it 'é a mesma fonte com prefixos diferentes ("AAAAAA+Arial" e "BBBBBB+Arial")' do
      leitor = Autonomia::Agents::Knowledge::Processors::PdfTrechos::Leitor.new

      expect(%i[AAAAAA+Arial BBBBBB+Arial Arial].map { |nome| leitor.send(:sem_subconjunto, nome) }).to eq(%w[Arial Arial Arial])
    end
  end

  describe 'o texto justificado que aperta as letras' do
    # Letras a -0,7 pt (Tc) e a palavra seguinte 2,5 pt adiante (TJ -250): a folga entre palavras fica em 1,8 pt, abaixo
    # dos 20% da letra com que o pdf-reader põe espaço, e o page.text colava "NAOFAZERNENHUMACORDO".
    let(:pdf) { pdf_com([[['', topo, 54, '-0.7 Tc [(NAO) -250 (FAZER) -250 (NENHUM) -250 (ACORDO)] TJ']]]) }

    it 'separa as palavras pela folga comum entre as letras', :aggregate_failures do
      expect(PDF::Reader.new(StringIO.new(pdf)).pages.first.text).to include('NAOFAZERNENHUMACORDO')
      expect(extrair).to include('NAO FAZER NENHUM ACORDO')
    end
  end

  describe 'duas linhas sobrepostas na mesma altura (célula de tabela)' do
    let(:pdf) { pdf_com([[['Comprovante de pagamento', topo, 54], ['instrumento.', topo + 2, 47]]]) }

    it 'não intercala as letras: cada uma fica inteira, separada por espaço' do
      expect(extrair).to include('instrumento. Comprovante de pagamento')
    end
  end

  describe 'a página curta' do
    let(:pdf) { pdf_com([corpo('Titulo curto', nil, 'Primeira linha do texto', 'segunda linha do texto')]) }

    it 'acha a quebra de parágrafo com só três linhas (a mediana de baixo)' do
      expect(extrair).to include("Titulo curto\n\nPrimeira linha do texto\nsegunda linha do texto")
    end
  end

  it 'PDF com menos de 4 páginas fica com o rodapé em toda página' do
    pdf_curto = pdf_com([pagina(definicoes, 1), pagina(definicoes, 2), pagina(definicoes, 3)])
    allow(file).to receive(:download).and_return(pdf_curto)

    expect(extrair.scan('Versao SETEMBRO-2026').size).to eq(3)
  end

  it 'página sem trecho de texto fica com o texto da main' do
    allow(Autonomia::Agents::Knowledge::Processors::PdfTrechos).to receive(:da_pagina).and_return([])

    expect(extrair.scan('Versao SETEMBRO-2026').size).to eq(4)
  end

  describe 'o que fica como na main' do
    it 'a Lia (instrução mantida), mesmo com a Fase 2 ligada' do
      Autonomia::Agents::Fase2.ligar!(account)
      lia = instance_double(Autonomia::Agents::Agent, instrucao_mantida?: true, config: {})

      expect(extrair(material(lia)).scan('Versao SETEMBRO-2026').size).to eq(4)
    end

    it 'o Guia (system_key)' do
      guia = instance_double(Autonomia::Agents::Agent, instrucao_mantida?: false, config: { 'system_key' => 'guia' })

      expect(extrair(material(guia)).scan('Versao SETEMBRO-2026').size).to eq(4)
    end

    it 'o anexo da conversa, o CRM e o Guia (objeto sem agente)' do
      anexo = Autonomia::Agents::Operate::MessageMedia::SourceLike.new(file, 'apolice.pdf', 'pdf')

      expect(described_class.new(anexo, ocr: false).extract.scan('Versao SETEMBRO-2026').size).to eq(4)
    end
  end
end
