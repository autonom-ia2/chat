require 'rails_helper'

# #1426 (PDF Suhai, 31/10) — o texto do PDF digitado sai em parágrafos pela posição das linhas na página, não pela grade do
# `page.text` (que punha linha em branco no meio do parágrafo e fazia o Chunker cortar a frase). PDF de verdade, montado
# em memória, com texto posicionado como num "Print To PDF": linhas a 13,2 pt, parágrafos a 26,4 pt, rodapé corrido.
RSpec.describe Autonomia::Agents::Knowledge::Processors::Pdf do
  let(:account) { create(:account) }
  let(:bia) { instance_double(Autonomia::Agents::Agent, instrucao_mantida?: false) }
  let(:file) { double('attachment', attached?: true, download: pdf) } # rubocop:disable RSpec/VerifiedDoubles
  let(:source) do
    double('source', reference: 'cg.pdf', source_type: 'pdf', file: file, account: account, agent: bia).tap do |fonte| # rubocop:disable RSpec/VerifiedDoubles
      allow(fonte).to receive(:paginas_de_fora=)
      allow(fonte).to receive(:secoes=)
    end
  end
  let(:linha) { 13.2 }
  let(:pdf) do
    pdf_com([pagina(sumario(780), 1), pagina(definicao(780), 2), pagina(definicao(780), 3), pagina(definicao(780), 4)])
  end

  # Uma página: [texto, y] de cada linha, mais o rodapé corrido.
  def pagina(linhas, numero)
    [*linhas, ['Versao SETEMBRO-2026', 15.6], [numero.to_s, 25.9]]
  end

  # Termo e definição em linhas seguidas; entre um termo e outro, o espaço de duas linhas.
  def definicao(topo)
    [['Dano Moral', topo], ['Ofensa aos principios e valores de ordem moral, tais como honra e dignidade', topo - linha],
     ['pessoal ou familiar. Cabe ao juiz do processo fixar o valor da reparacao.', topo - (2 * linha)],
     ['Dano Material', topo - (4 * linha)], ['Dano causado exclusivamente a propriedade material de pessoas.', topo - (5 * linha)]]
  end

  def sumario(topo)
    [['Sumario', topo], ["1. OBJETIVO DO SEGURO#{'.' * 60}4", topo - (2 * linha)], ["2. COBERTURAS#{'.' * 60}5", topo - (3 * linha)]]
  end

  # PDF mínimo com Helvetica: cada linha é um "Td" na altura dada.
  def pdf_com(paginas)
    fonte = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    conteudos = paginas.map do |linhas|
      corpo = linhas.map { |texto, y| "BT /F1 10 Tf 54 #{y} Td (#{texto}) Tj ET" }.join("\n")
      "<< /Length #{corpo.bytesize} >>\nstream\n#{corpo}\nendstream"
    end
    n = paginas.size
    paginas_ids = (0...n).map { |i| 4 + (2 * i) }
    objetos = ['<< /Type /Catalog /Pages 2 0 R >>',
               "<< /Type /Pages /Kids [#{paginas_ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{n} >>", fonte]
    conteudos.each_with_index do |conteudo, i|
      objetos << '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> ' \
                 "/Contents #{paginas_ids[i] + 1} 0 R >>"
      objetos << conteudo
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

  context 'with the Fase 2 on' do
    before { Autonomia::Agents::Fase2.ligar!(account) }

    it 'junta as linhas do mesmo parágrafo e separa parágrafos pelo espaço entre eles', :aggregate_failures do
      texto = described_class.new(source).extract

      expect(texto).to include("Dano Moral\nOfensa aos principios e valores de ordem moral, tais como honra e dignidade\n" \
                               "pessoal ou familiar. Cabe ao juiz do processo fixar o valor da reparacao.\n\nDano Material\n")
    end

    it 'deixa o cabeçalho/rodapé corrido só na primeira página, e o resto do texto', :aggregate_failures do
      texto = described_class.new(source).extract

      expect(texto.scan('Versao SETEMBRO-2026').size).to eq(1)
      expect(texto).to include('2. COBERTURAS')
    end

    it 'linha repetida no topo das páginas (título de tabela) fica na primeira vez; repetida no meio do corpo, fica sempre' do
      texto = described_class.new(source).extract

      expect([texto.scan('Dano Moral').size, texto.scan('Dano Material').size]).to eq([1, 3])
    end

    it 'o Chunker não corta mais a frase no meio: a definição inteira fica num trecho só' do
      chunks = Autonomia::Agents::Knowledge::Chunker.new(described_class.new(source).extract, source_type: 'pdf').chunks

      expect(chunks).to include(a_string_including('dignidade pessoal ou familiar. Cabe ao juiz'))
    end

    it 'página que perderia texto na remontagem fica com o texto da main' do
      allow_any_instance_of(PDF::Reader::Page).to receive(:runs).and_return([]) # rubocop:disable RSpec/AnyInstance

      expect(described_class.new(source).extract.scan('Versao SETEMBRO-2026').size).to eq(4)
    end
  end

  it 'fora da Fase 2, o texto é o da main (com o rodapé em toda página)' do
    expect(described_class.new(source).extract.scan('Versao SETEMBRO-2026').size).to eq(4)
  end

  it 'na Lia, o texto é o da main' do
    Autonomia::Agents::Fase2.ligar!(account)
    allow(bia).to receive(:instrucao_mantida?).and_return(true)

    expect(described_class.new(source).extract.scan('Versao SETEMBRO-2026').size).to eq(4)
  end
end
