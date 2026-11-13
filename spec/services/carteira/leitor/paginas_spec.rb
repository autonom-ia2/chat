require 'rails_helper'
require 'pdf-reader'

# E6 (#2899): quais páginas de um PDF vão ao modelo. Dados fictícios; os PDFs daqui são montados na hora.
RSpec.describe Carteira::Leitor::Paginas do
  let(:processadores) { Autonomia::Agents::Knowledge::Processors }
  let(:longa) { CarteiraPdfLongo.caminho }
  let(:lido_no_ocr) { 'Apólice nº: EX-0001 lida pelo OCR da página escaneada' }

  before do
    allow(processadores::Rasterizacao).to receive(:pagina) { |_pdf, _indice, **_opcoes, &bloco| bloco.call('pagina.png') }
    allow(processadores::Ocr).to receive(:ler).and_return(lido_no_ocr)
  end

  # Um PDF com uma página por item: texto, ou :sem_texto para a página que só tem desenho.
  def com_pdf(paginas, tamanho: 10, senha: nil)
    Tempfile.create(['paginas', '.pdf']) do |arquivo|
      Prawn::Document.generate(arquivo.path, page_size: 'A4') do |documento|
        documento.encrypt_document(user_password: senha, owner_password: "dono-#{senha}") if senha
        documento.font_size tamanho
        paginas.each_with_index do |conteudo, indice|
          documento.start_new_page unless indice.zero?
          conteudo == :sem_texto ? documento.stroke_rectangle([50, 500], 200, 100) : documento.text(conteudo)
        end
      end
      yield arquivo.path
    end
  end

  def numeros(caminho, **opcoes)
    described_class.new(caminho, **opcoes).escolhidas.map(&:numero)
  end

  it 'sem documento nem nome, escolhe as primeiras páginas, e não as 160' do
    paginas = described_class.new(longa)

    expect(paginas.escolhidas.map(&:numero)).to eq([1, 2, 3, 4])
    expect(paginas.total).to eq(160)
    expect(paginas.escolhidas.first.texto).to include('RS-0114.000777')
  end

  # Achado I da revisão: a vigência e o prêmio costumam estar na página ao lado da que traz o CPF.
  it 'com o CPF, escolhe as páginas em que os dígitos dele aparecem, escrito com ou sem pontuação, e as vizinhas de cada uma' do
    expect(numeros(longa, documento: '987.654.321-99')).to eq([1, 2, 3, 159, 160])
    expect(numeros(longa, documento: '98765432199')).to eq([1, 2, 3, 159, 160])
  end

  it 'as vizinhas entram só no que sobra do teto: as páginas do CPF vêm todas, e o total nunca passa do máximo' do
    paginas = Array.new(10) { |indice| "Página #{indice + 1} das condições gerais do seguro" }
    [1, 4, 7].each { |indice| paginas[indice] = 'Dados do segurado de CPF 111.222.333-00' }

    com_pdf(paginas) { |caminho| expect(numeros(caminho, documento: '111.222.333-00')).to eq([1, 2, 3, 4, 5, 8]) }
  end

  it 'com o nome, escolhe as páginas em que ele aparece, sem contar caixa, acento e espaço' do
    expect(numeros(longa, nome: 'renata  AMOSTRA límã')).to eq([1, 2, 160])
  end

  it 'o documento vale mais que o nome; se ele não aparece em página nenhuma, vale o nome; sem nenhum, as primeiras' do
    paginas = ['Dados do segurado: Ana Modelo, residente em Cidade Exemplo', 'Documento do segurado: CPF 111.222.333-00, conforme cadastro',
               'Anexo de cobrança em nome de Ana Modelo, débito em conta', 'Condições gerais do seguro, sem dado de segurado nenhum']

    com_pdf(paginas) do |caminho|
      expect(numeros(caminho, documento: '111.222.333-00', nome: 'Ana Modelo')).to eq([1, 2, 3])
      expect(numeros(caminho, documento: '999.888.777-66', nome: 'Ana Modelo')).to eq([1, 3])
      expect(numeros(caminho, documento: '999.888.777-66', nome: 'Outra Pessoa')).to eq([1, 2, 3, 4])
    end
  end

  it 'documento com tamanho que não é de CPF nem de CNPJ e nome curto demais não escolhem nada' do
    paginas = ['Dados do segurado: Ana Modelo, CPF 111.222.333-00', 'Página dois das condições gerais do seguro',
               'Página três, com o anexo de cobrança da Ana']

    com_pdf(paginas) do |caminho|
      expect(numeros(caminho, documento: '111.222')).to eq([1, 2, 3])
      expect(numeros(caminho, nome: 'Ana')).to eq([1, 2, 3])
    end
  end

  it 'nunca escolhe mais que o máximo, mesmo com o documento em todas as páginas' do
    com_pdf(Array.new(10) { |indice| "Página #{indice + 1} do segurado de CPF 111.222.333-00" }) do |caminho|
      expect(numeros(caminho, documento: '11122233300')).to eq((1..described_class::MAXIMO).to_a)
    end
  end

  it 'corta cada página no teto de caracteres' do
    com_pdf([Array.new(1_500) { 'apólice' }.join(' ')], tamanho: 3) do |caminho|
      pagina = described_class.new(caminho).escolhidas.first

      expect(pagina.texto.length).to eq(described_class::MAXIMO_POR_PAGINA)
    end
  end

  describe 'página sem texto' do
    it 'sem OCR, fica de fora e nada é rasterizado' do
      com_pdf([:sem_texto, 'Condições gerais do seguro, página dois']) do |caminho|
        expect(numeros(caminho)).to eq([2])
      end
      expect(processadores::Rasterizacao).not_to have_received(:pagina)
    end

    it 'com OCR, só a página escolhida sem texto é lida pelo OCR' do
      com_pdf([:sem_texto, 'Condições gerais do seguro, página dois']) do |caminho|
        paginas = described_class.new(caminho, ocr: true).escolhidas

        expect(paginas.map(&:numero)).to eq([1, 2])
        expect(paginas.first.texto).to eq(lido_no_ocr)
        expect(processadores::Rasterizacao).to have_received(:pagina).once.with(caminho, 0)
      end
    end

    it 'com OCR, a página sem texto que não foi escolhida não é lida' do
      paginas = Array.new(6) { |indice| "Página #{indice + 1} das condições gerais do seguro" }.insert(4, :sem_texto)

      com_pdf(paginas) { |caminho| expect(numeros(caminho, ocr: true)).to eq([1, 2, 3, 4]) }
      expect(processadores::Rasterizacao).not_to have_received(:pagina)
    end

    it 'OCR que falha, ou máquina sem o tesseract, deixa a página de fora e não levanta' do
      [processadores::Ocr::Falhou.new('tesseract_timeout'), processadores::Ocr::Indisponivel.new('tesseract_missing'),
       processadores::Rasterizacao::Falhou.new('rasterizacao_timeout')].each do |erro|
        allow(processadores::Ocr).to receive(:ler).and_raise(erro)

        com_pdf([:sem_texto, 'Condições gerais do seguro, página dois']) { |caminho| expect(numeros(caminho, ocr: true)).to eq([2]) }
      end
    end

    it 'PDF inteiro sem texto e sem OCR não tem página para mandar' do
      com_pdf([:sem_texto]) { |caminho| expect(numeros(caminho)).to eq([]) }
    end
  end

  describe 'arquivo que não abre' do
    let(:ilegivel) { described_class::Ilegivel }

    def abrir(caminho)
      described_class.new(caminho).escolhidas
    end

    it 'arquivo que não é PDF, ou que o leitor de PDF não entende, é ilegível' do
      ['texto puro', '%PDF-1.4 e depois lixo'].each do |conteudo|
        Tempfile.create(['arquivo', '.pdf']) do |arquivo|
          arquivo.write(conteudo)
          arquivo.flush

          expect { abrir(arquivo.path) }.to raise_error(ilegivel)
        end
      end
    end

    # Achado F da revisão: qualquer erro de abertura vira Ilegivel, nunca outro erro.
    it 'caminho que não existe é ilegível' do
      expect { abrir('/caminho/que/nao/existe.pdf') }.to raise_error(ilegivel)
      expect { abrir(Rails.root.join('spec/fixtures/carteira').to_s) }.to raise_error(ilegivel)
    end

    it 'PDF com senha é ilegível' do
      com_pdf(['Apólice com senha de abertura'], senha: 'senha-de-exemplo') { |caminho| expect { abrir(caminho) }.to raise_error(ilegivel) }
    end

    it 'PDF cortado no meio é ilegível' do
      inteiro = File.binread(longa)

      Tempfile.create(['cortado', '.pdf'], binmode: true) do |arquivo|
        arquivo.write(inteiro.first(inteiro.bytesize / 2))
        arquivo.flush

        expect { abrir(arquivo.path) }.to raise_error(ilegivel)
      end
    end

    # Segunda revisão: a classe do erro vai para o registro, para um defeito nosso não se esconder atrás de "ilegível".
    it 'erro que o leitor de PDF não previu também vira ilegível, e o registro leva só a classe do erro' do
      allow(PDF::Reader).to receive(:new).and_raise(NoMethodError, 'undefined method para o texto da apólice')
      allow(Rails.logger).to receive(:warn)

      expect { abrir(longa) }.to raise_error(ilegivel, 'NoMethodError')
      expect(Rails.logger).to have_received(:warn).once.with('[carteira][leitor] pdf_nao_abriu NoMethodError')
    end

    # Terceira revisão: o resgate amplo fica só em volta do leitor de PDF. Erro nosso nas conferências de antes sobe.
    it 'erro de programação na conferência do arquivo sobe, não vira ilegível' do
      allow(processadores::Rasterizacao).to receive(:pdf?).and_raise(NoMethodError)

      expect { abrir(longa) }.to raise_error(NoMethodError)
    end

    it 'o inspect e o JSON da página mostram só o número, nunca o texto' do
      pagina = described_class::Pagina.new(numero: 3, texto: 'Marina Exemplo de Souza')

      expect([pagina.inspect, pagina.to_s]).to all(eq('#<Carteira::Leitor::Paginas::Pagina numero=3 caracteres=23>'))
      expect([pagina.as_json, [pagina].to_json]).to eq([{ 'numero' => 3 }, '[{"numero":3}]'])
    end

    it 'o inspect e o JSON das páginas não mostram o caminho, o documento nem o texto' do
      paginas = described_class.new(longa, documento: '987.654.321-99', nome: 'Renata Amostra Lima')
      paginas.escolhidas

      expect([paginas.inspect, paginas.to_json]).to eq(['#<Carteira::Leitor::Paginas>', '{"classe":"Carteira::Leitor::Paginas"}'])
    end

    it 'erro ao ler o texto de uma página deixa a página de fora, não levanta, e o registro leva a classe do erro' do
      quebrada = instance_double(PDF::Reader::Page)
      allow(quebrada).to receive(:text).and_raise(TypeError, 'texto da apólice')
      boa = instance_double(PDF::Reader::Page, text: 'Condições gerais do seguro, página dois')
      allow(PDF::Reader).to receive(:new).and_return(instance_double(PDF::Reader, pages: [quebrada, boa]))
      allow(Rails.logger).to receive(:warn)

      expect(numeros(longa)).to eq([2])
      expect(Rails.logger).to have_received(:warn).once.with('[carteira][leitor] pagina_ilegivel pagina=1 TypeError')
    end

    # Achado G da revisão: o tamanho é conferido antes de o leitor de PDF tocar no arquivo.
    it 'arquivo maior que o teto é ilegível, sem abrir' do
      stub_const("#{described_class}::MAXIMO_DE_BYTES", 1_000)
      allow(PDF::Reader).to receive(:new).and_call_original

      expect { abrir(longa) }.to raise_error(ilegivel, 'grande_demais')
      expect(PDF::Reader).not_to have_received(:new)
    end

    it 'o teto é o limite de anexo que a carteira pratica para o PDF da apólice' do
      expect(described_class::MAXIMO_DE_BYTES).to eq(Carteira::Pdf::LIMITE_PADRAO_MB.megabytes)
    end
  end
end
