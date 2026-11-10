require 'rails_helper'

# #1431 (F1) — com a flag rag_corte_por_estrutura, o PDF da base entrega também os blocos (título com nível, parágrafo,
# página), lidos só pela geometria: letra maior que a do corpo, ou linha curta em outra fonte, é título; o título que
# quebra em duas linhas é um título só; a página de sumário sai. PDF de verdade, montado em memória.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  let(:account) { create(:account) }
  let(:bia) { instance_double(Autonomia::Agents::Agent, instrucao_mantida?: false, config: {}) }
  let(:file) { double('attachment', attached?: true, download: pdf) } # rubocop:disable RSpec/VerifiedDoubles
  let(:source) do
    double('source', reference: 'cg.pdf', source_type: 'pdf', file: file, account: account, agent: bia).tap do |fonte| # rubocop:disable RSpec/VerifiedDoubles
      allow(fonte).to receive(:paginas_de_fora=)
      allow(fonte).to receive(:secoes=)
      allow(fonte).to receive(:blocos=)
    end
  end
  let(:topo) { 780 }
  let(:linha) { 13.2 }
  let(:corpo1) { 'O seguro cobre os danos materiais causados ao veiculo segurado por colisao, incendio e roubo,' }
  let(:corpo2) { 'conforme as condicoes desta apolice e os limites contratados pelo segurado na proposta.' }
  let(:pdf) { pdf_com([sumario, coberturas, tabela, assistencia, percentuais, planos]) }

  # [texto, y, fonte, tamanho]: F1 Helvetica, F2 Helvetica-Bold. O sumário tem rodapé que termina no número da página
  # (só nesta página, então o PdfParagrafos não o tira como rodapé corrido): ele não pode impedir o sumário de sair.
  def sumario
    [["Sumario#{' ' * 1}", topo, 'F2', 10],
     ["1. OBJETIVO DO SEGURO #{'.' * 70} 2", topo - 26.4, 'F1', 10],
     ["2. COBERTURAS #{'.' * 80} 2", topo - 39.6, 'F1', 10],
     ["3. FRANQUIA #{'.' * 84} 3", topo - 52.8, 'F1', 10],
     ["4. EXCLUSOES #{'.' * 82} 3", topo - 66, 'F1', 10],
     ["9. TABELA DE INVALIDEZ #{'.' * 68} 3", topo - 79.2, 'F1', 10],
     ['Condicoes Gerais Auto - Processo SUSEP 15414.004192/2004-71 - Versao 3.0. 1', 40, 'F1', 8],
     ['1', 25.9, 'F1', 10]]
  end

  def coberturas
    [['2. COBERTURAS', topo, 'F1', 14],
     [corpo1, topo - 26.4, 'F1', 10], [corpo2, topo - 26.4 - linha, 'F1', 10],
     ['2', 25.9, 'F1', 10]]
  end

  def tabela
    [['9 - TABELA PARA CALCULO DA INDENIZACAO', topo, 'F2', 10],
     ['EM CASO DE INVALIDEZ PERMANENTE', topo - linha, 'F2', 10],
     ['Perda total do uso de um dos bracos, em percentual sobre a importancia segurada da cobertura,', topo - 39.6, 'F1', 10],
     ['conforme a tabela da SUSEP para invalidez permanente total ou parcial por acidente pessoal.', topo - 39.6 - linha, 'F1', 10],
     ['3', 25.9, 'F1', 10]]
  end

  # O número da página só sai em PDF de 4 páginas ou mais (PdfParagrafos::CORRIDO_MIN_PAGINAS). A letra do título, 13,9,
  # difere da do "2. COBERTURAS" (14) bem menos que TROCA_DE_LETRA: o mesmo nível.
  def assistencia
    [['3. ASSISTENCIA', topo, 'F1', 13.9], [corpo1, topo - 26.4, 'F1', 10], ['4', 25.9, 'F1', 10]]
  end

  # Tabela de percentuais: quase toda linha termina num número, mas os números não crescem como num sumário.
  def percentuais
    [['Perda total da visao de um olho 30', topo, 'F1', 10],
     ['Surdez total incuravel de ambos os ouvidos 40', topo - 26.4, 'F1', 10],
     ['Surdez total incuravel de um dos ouvidos 20', topo - 52.8, 'F1', 10],
     ['Alienacao mental total e incuravel 100', topo - 79.2, 'F1', 10],
     ['Fratura nao consolidada do maxilar inferior 20', topo - 105.6, 'F1', 10],
     ['5', 25.9, 'F1', 10]]
  end

  # Tabela de planos: os números crescem e cabem nas páginas do documento, como num sumário, mas não há linha de pontos.
  def planos
    [['Plano Basico com assistencia local 1', topo, 'F1', 10],
     ['Plano Medio com assistencia estadual 2', topo - 26.4, 'F1', 10],
     ['Plano Plus com assistencia nacional 4', topo - 52.8, 'F1', 10],
     ['Plano Top com assistencia internacional 5', topo - 79.2, 'F1', 10],
     ['6', 25.9, 'F1', 10]]
  end

  def pdf_com(paginas)
    ids = paginas.each_index.map { |indice| 5 + (2 * indice) }
    objetos = ['<< /Type /Catalog /Pages 2 0 R >>',
               "<< /Type /Pages /Kids [#{ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{paginas.size} >>",
               '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>']
    paginas.each_with_index do |linhas, indice|
      conteudo = linhas.map { |texto, y, fonte, tamanho, x = 54| "BT /#{fonte} #{tamanho} Tf #{x} #{y} Td (#{texto}) Tj ET" }.join("\n")
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

  def blocos_gravados
    gravados = nil
    allow(source).to receive(:blocos=) { |blocos| gravados = blocos }
    described_class.new(source).extract
    gravados
  end

  context 'with the flag on' do
    before { account.enable_features!('rag_corte_por_estrutura') }

    it 'reads a title by the bigger letter and its paragraph with the page', :aggregate_failures do
      blocos = blocos_gravados

      expect(blocos).to include({ tipo: :titulo, nivel: 1, texto: '2. COBERTURAS', pagina: 2 })
      expect(blocos).to include({ tipo: :paragrafo, texto: "#{corpo1}\n#{corpo2}", itens: ["#{corpo1}\n#{corpo2}"], pagina: 2 })
    end

    it 'reads a title broken in two lines as one title, below the bigger one' do
      expect(blocos_gravados).to include(
        { tipo: :titulo, nivel: 2, texto: '9 - TABELA PARA CALCULO DA INDENIZACAO EM CASO DE INVALIDEZ PERMANENTE', pagina: 3 }
      )
    end

    it 'leaves the table of contents and the page numbers out', :aggregate_failures do
      blocos = blocos_gravados

      expect(blocos.map { |bloco| bloco[:pagina] }.uniq).to eq([2, 3, 4, 5, 6])
      expect(blocos.pluck(:texto)).not_to include('2', '3', '4', '5', '6')
    end

    it 'keeps a table whose lines end in numbers that do not grow like page numbers' do
      expect(blocos_gravados.pluck(:texto).join("\n")).to include('Surdez total incuravel de um dos ouvidos 20',
                                                                  'Fratura nao consolidada do maxilar inferior 20')
    end

    it 'keeps a table whose numbers grow like page numbers but has no dot leader' do
      expect(blocos_gravados.pluck(:texto).join("\n")).to include('Plano Top com assistencia internacional 5')
    end

    it 'gives the same level to title letters closer than the letter change' do
      expect(blocos_gravados).to include({ tipo: :titulo, nivel: 1, texto: '3. ASSISTENCIA', pagina: 4 })
    end

    it 'keeps the text the processor returns as before' do
      expect(described_class.new(source).extract).to include("2. COBERTURAS\n\n#{corpo1}\n#{corpo2}")
    end

    # PR 1b: tabela por célula, item de lista pela linha curta; a linha que se repete no alto das páginas sai, e a do pé
    # (mesmo com o número da página no fim) fica só na primeira vez.
    context 'with a table, a list and running lines' do
      let(:pdf) { pdf_com([prazo_curto, *(2..4).map { |numero| pagina_simples(numero) }]) }

      def bordas(numero)
        [['Voltar ao sumario', 815, 'F1', 10],
         ["Clausula #{numero}", 800, 'F1', 10, 300], ['Condicoes Gerais - Versao 3.0.', 20, 'F1', 8], [numero.to_s, 20, 'F1', 8, 540]]
      end

      def prazo_curto
        [*bordas(1), ['1. PRAZO CURTO', topo, 'F1', 14],
         [corpo1, topo - 26.4, 'F1', 10], ['coberto pelo seguro;', topo - 26.4 - linha, 'F1', 10],
         ['b- Custos da blindagem do veiculo;', topo - 26.4 - (2 * linha), 'F1', 10],
         ['Prazo', 680, 'F2', 10], ['% do premio', 680, 'F2', 10, 200],
         ['1 a 15', 660, 'F1', 10], ['13%', 660, 'F1', 10, 200],
         ['16 a 30', 640, 'F1', 10], ['20%', 640, 'F1', 10, 200],
         ['31 a 45', 620, 'F1', 10], ['27%', 620, 'F1', 10, 200],
         [corpo2, 590, 'F1', 10]]
      end

      def pagina_simples(numero)
        [*bordas(numero), ["#{numero + 1}. CLAUSULA", topo, 'F1', 14], [corpo1, topo - 26.4, 'F1', 10], [corpo2, topo - 26.4 - linha, 'F1', 10]]
      end

      it 'reads the table rows with the header of each column', :aggregate_failures do
        tabela = blocos_gravados.find { |bloco| bloco[:tipo] == :tabela }

        expect(tabela).to include(pagina: 1, texto: tabela[:itens].join("\n"))
        expect(tabela[:itens]).to eq(['Prazo: 1 a 15 | % do premio: 13%', 'Prazo: 16 a 30 | % do premio: 20%',
                                      'Prazo: 31 a 45 | % do premio: 27%'])
      end

      it 'splits the paragraph in items where a line ends before the margin' do
        lista = blocos_gravados.find { |bloco| bloco[:texto].start_with?(corpo1) && bloco[:pagina] == 1 }

        expect(lista[:itens]).to eq(["#{corpo1}\ncoberto pelo seguro;", 'b- Custos da blindagem do veiculo;'])
      end

      it 'drops a line repeated at the top of the pages and keeps one at the foot only once, even with the page number' do
        textos = blocos_gravados.pluck(:texto).join("\n")

        expect([textos.scan('Voltar ao sumario').size, textos.scan('Condicoes Gerais - Versao 3.0.').size]).to eq([0, 1])
        expect(textos).to include('Clausula 1', 'Clausula 2', 'Clausula 3', 'Clausula 4')
      end

      # A 1ª página é sumário e sai: a linha do pé lida lá não conta como já vista, e ela fica uma vez nas outras.
      context 'when the first page is the table of contents' do
        let(:pdf) { pdf_com([[*bordas(1), *sumario.first(6)], *(2..4).map { |numero| pagina_simples(numero) }]) }

        it 'keeps the foot line once' do
          expect(blocos_gravados.pluck(:texto).join("\n").scan('Condicoes Gerais - Versao 3.0.').size).to eq(1)
        end
      end
    end

    # #2845 — o título curto em negrito, seguido do item que começa com o número em negrito e segue no texto comum.
    context 'with a bold title followed by an item that starts with a bold number' do
      let(:pdf) do
        pdf_com([[['1.3. AMBITO GEOGRAFICO DA COBERTURA', topo, 'F2', 10],
                  ['1.3.1.', topo - linha, 'F2', 10], ['As condicoes desta cobertura valem em todo o territorio', topo - linha, 'F1', 10, 100],
                  ['nacional, salvo quando a apolice disser outra coisa sobre o local do evento.', topo - (2 * linha), 'F1', 10]]])
      end

      it 'reads the title as a title, apart from the item' do
        expect(blocos_gravados).to include(a_hash_including(tipo: :titulo, texto: '1.3. AMBITO GEOGRAFICO DA COBERTURA', pagina: 1))
      end
    end

    # #2845 — a ênfase em negrito no fim do parágrafo, terminando numa linha curta toda em negrito, não é título.
    context 'with a bold emphasis that ends the paragraph in a short line' do
      let(:pdf) do
        pdf_com([[['Se ficar comprovado na regulacao do sinistro que houve ma-fe na declaracao do risco, ou que foi', topo, 'F1', 10],
                  ['o segurado que agravar o risco de forma intencional', topo - linha, 'F1', 10],
                  ['O SEGURADO PERDERA O DIREITO', topo - linha, 'F2', 10, 320],
                  ['A INDENIZACAO.', topo - (2 * linha), 'F2', 10]]])
      end

      it 'reads no title' do
        expect(blocos_gravados.pluck(:tipo)).not_to include(:titulo)
      end
    end

    # #2862 — dois títulos seguidos, sem texto entre eles, com um pouco mais de espaço que o de linha: o de baixo caberia
    # inteiro no fim da linha de cima, então não é a quebra de um título só.
    context 'with two titles in sequence' do
      let(:pdf) do
        pdf_com([[['CLAUSULA 2 - CONTRATACAO', topo, 'F2', 10], ['2.1. ACEITACAO', topo - 16.4, 'F2', 10],
                  [corpo1, topo - 30.9, 'F1', 10], [corpo2, topo - 30.9 - linha, 'F1', 10], [corpo1, topo - 30.9 - (2 * linha), 'F1', 10]]])
      end

      it 'reads two titles' do
        expect(blocos_gravados.select { |bloco| bloco[:tipo] == :titulo }.pluck(:texto)).to eq(['CLAUSULA 2 - CONTRATACAO', '2.1. ACEITACAO'])
      end
    end

    # #2862 — o título longo que quebra porque não cabe na linha continua um título só, mesmo com o mesmo espaço.
    context 'with a long title that wraps' do
      let(:pdf) do
        pdf_com([[['COBERTURA ADICIONAL DE RESPONSABILIDADE CIVIL FAMILIAR E DANOS MORAIS A TERCEIROS', topo, 'F2', 10],
                  ['DO IMOVEL', topo - 16.4, 'F2', 10],
                  [corpo1, topo - 30.9, 'F1', 10], [corpo2, topo - 30.9 - linha, 'F1', 10], [corpo1, topo - 30.9 - (2 * linha), 'F1', 10]]])
      end

      it 'reads one title' do
        expect(blocos_gravados.select { |bloco| bloco[:tipo] == :titulo }.pluck(:texto))
          .to eq(['COBERTURA ADICIONAL DE RESPONSABILIDADE CIVIL FAMILIAR E DANOS MORAIS A TERCEIROS DO IMOVEL'])
      end
    end

    # #2863 — títulos da mesma letra e da mesma fonte: o nível vem da numeração (1., 2.1.) e o título sem número fica acima
    # dos numerados; o marcador de item ("a)") fica abaixo deles.
    context 'with titles of the same letter and font' do
      let(:pdf) do
        pdf_com([[['COBERTURA ADICIONAL DE ALAGAMENTO', topo, 'F2', 10], ['1. RISCOS COBERTOS', topo - 16.4, 'F2', 10],
                  *secao(topo - 30.9), ['2. EXCLUSOES', topo - 90, 'F2', 10], *secao(topo - 90 - linha),
                  ['2.1. DANOS AO JARDIM', topo - 160, 'F2', 10], *secao(topo - 160 - linha),
                  ['a\\) Pessoa Fisica:', topo - 230, 'F2', 10], *secao(topo - 230 - linha)]])
      end

      # Três linhas de corpo: a seção curta (abaixo do PISO do corte) seria juntada à seguinte.
      def secao(inicio)
        [[corpo1, inicio, 'F1', 10], [corpo2, inicio - linha, 'F1', 10], [corpo1, inicio - (2 * linha), 'F1', 10]]
      end

      def niveis
        blocos_gravados.select { |bloco| bloco[:tipo] == :titulo }.to_h { |bloco| [bloco[:texto], bloco[:nivel]] }
      end

      it 'puts the title without a number above the numbered ones, and the numbers by depth', :aggregate_failures do
        nivel = niveis

        expect(nivel['COBERTURA ADICIONAL DE ALAGAMENTO']).to be < nivel['1. RISCOS COBERTOS']
        expect(nivel['1. RISCOS COBERTOS']).to eq(nivel['2. EXCLUSOES'])
        expect(nivel['2. EXCLUSOES']).to be < nivel['2.1. DANOS AO JARDIM']
        expect(nivel['2.1. DANOS AO JARDIM']).to be < nivel['a) Pessoa Fisica:']
      end

      it 'keeps the parent title in the path of the section' do
        trechos = Autonomia::Agents::Knowledge::CortePorSecao.new(blocos_gravados, documento: 'cg.pdf').trechos

        expect(trechos.map { |trecho| trecho[:metadata][:caminho] })
          .to include(['cg.pdf', 'COBERTURA ADICIONAL DE ALAGAMENTO', '1. RISCOS COBERTOS'],
                      ['cg.pdf', 'COBERTURA ADICIONAL DE ALAGAMENTO', '2. EXCLUSOES', '2.1. DANOS AO JARDIM'])
      end
    end

    # #2863 — o título sem número no meio da seção (um rótulo entre "2.1." e "2.2.") fica no nível do último numerado: não
    # vira pai das seções seguintes. O sem número que abre outra numeração ("CLAUSULA 3" antes do "3.1.") continua acima.
    context 'with a title without a number between numbered titles' do
      let(:pdf) do
        pdf_com([[['2. EXCLUSOES', topo, 'F2', 10], *secao(topo - linha),
                  ['2.1. DANOS AO JARDIM', topo - 70, 'F2', 10], *secao(topo - 70 - linha),
                  ['OBSERVACAO IMPORTANTE', topo - 140, 'F2', 10], *secao(topo - 140 - linha),
                  ['2.2. DANOS ELETRICOS', topo - 210, 'F2', 10], *secao(topo - 210 - linha),
                  ['CLAUSULA 3 - PAGAMENTO', topo - 280, 'F2', 10], *secao(topo - 280 - linha),
                  ['3.1. PRAZO CURTO', topo - 350, 'F2', 10], *secao(topo - 350 - linha)]])
      end

      def secao(inicio)
        [[corpo1, inicio, 'F1', 10], [corpo2, inicio - linha, 'F1', 10], [corpo1, inicio - (2 * linha), 'F1', 10]]
      end

      it 'keeps the label as a sibling and the opening title above its numbers', :aggregate_failures do
        trechos = Autonomia::Agents::Knowledge::CortePorSecao.new(blocos_gravados, documento: 'cg.pdf').trechos
        caminhos = trechos.map { |trecho| trecho[:metadata][:caminho] }

        expect(caminhos).to include(['cg.pdf', '2. EXCLUSOES', '2.2. DANOS ELETRICOS'],
                                    ['cg.pdf', 'CLAUSULA 3 - PAGAMENTO', '3.1. PRAZO CURTO'])
        expect(caminhos.flatten.count('OBSERVACAO IMPORTANTE')).to eq(1)
      end
    end

    # #2863 — a linha curta em negrito que termina a frase do parágrafo de cima (a linha de cima vai até a margem, com o
    # espaço de linha normal) não é título: sem isso, o título sem número viraria pai de todas as seções seguintes.
    context 'with a short bold line that ends the paragraph above' do
      let(:pdf) do
        pdf_com([[[corpo2, topo, 'F1', 10], [corpo1, topo - linha, 'F1', 10], ['contato.dados.exemplo.', topo - (2 * linha), 'F2', 10],
                  ['1.2.', topo - (2 * linha) - 14.9, 'F2', 10], [corpo2, topo - (2 * linha) - 14.9, 'F1', 10, 100],
                  [corpo1, topo - (3 * linha) - 14.9, 'F1', 10], [corpo2, topo - (4 * linha) - 14.9, 'F1', 10]]])
      end

      it 'reads no title' do
        expect(blocos_gravados.pluck(:tipo)).not_to include(:titulo)
      end
    end

    context 'with a bold title after a paragraph that ends before the margin' do
      let(:pdf) do
        pdf_com([[[corpo1, topo, 'F1', 10], ['coberto pelo seguro.', topo - linha, 'F1', 10], ['2. EXCLUSOES', topo - (2 * linha), 'F2', 10],
                  [corpo1, topo - (3 * linha), 'F1', 10], [corpo2, topo - (4 * linha), 'F1', 10]]])
      end

      it 'still reads the title' do
        expect(blocos_gravados).to include(a_hash_including(tipo: :titulo, texto: '2. EXCLUSOES'))
      end
    end

    it 'gives no blocks to the protected agent (Lia)' do
      allow(bia).to receive(:instrucao_mantida?).and_return(true)

      described_class.new(source).extract

      expect(source).not_to have_received(:blocos=)
    end
  end

  it 'gives no blocks with the flag off' do
    described_class.new(source).extract

    expect(source).not_to have_received(:blocos=)
  end
end
