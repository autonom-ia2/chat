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

  # [texto, y, fonte, tamanho]: F1 Helvetica, F2 Helvetica-Bold.
  def sumario
    [["Sumario#{' ' * 1}", topo, 'F2', 10],
     ["1. OBJETIVO DO SEGURO #{'.' * 70} 2", topo - 26.4, 'F1', 10],
     ["2. COBERTURAS #{'.' * 80} 2", topo - 39.6, 'F1', 10],
     ["3. FRANQUIA #{'.' * 84} 3", topo - 52.8, 'F1', 10],
     ["4. EXCLUSOES #{'.' * 82} 3", topo - 66, 'F1', 10],
     ["9. TABELA DE INVALIDEZ #{'.' * 68} 3", topo - 79.2, 'F1', 10],
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
      conteudo = linhas.map { |texto, y, fonte, tamanho| "BT /#{fonte} #{tamanho} Tf 54 #{y} Td (#{texto}) Tj ET" }.join("\n")
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
      expect(blocos).to include({ tipo: :paragrafo, texto: "#{corpo1}\n#{corpo2}", pagina: 2 })
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
