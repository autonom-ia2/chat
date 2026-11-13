require 'rails_helper'

# E6 (#2899): quais páginas de um PDF vão ao modelo. Dados fictícios; os PDFs daqui são montados na hora.
RSpec.describe Carteira::Leitor::Paginas do
  let(:processadores) { Autonomia::Agents::Knowledge::Processors }
  let(:longa) { Rails.root.join('spec/fixtures/carteira/apolice_longa.pdf').to_s }
  let(:lido_no_ocr) { 'Apólice nº: EX-0001 lida pelo OCR da página escaneada' }

  before do
    allow(processadores::Rasterizacao).to receive(:pagina) { |_pdf, _indice, **_opcoes, &bloco| bloco.call('pagina.png') }
    allow(processadores::Ocr).to receive(:ler).and_return(lido_no_ocr)
  end

  # Um PDF com uma página por item: texto, ou :sem_texto para a página que só tem desenho.
  def com_pdf(paginas, tamanho: 10)
    Tempfile.create(['paginas', '.pdf']) do |arquivo|
      Prawn::Document.generate(arquivo.path, page_size: 'A4') do |documento|
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

  it 'com o CPF, escolhe as páginas em que os dígitos dele aparecem, escrito com ou sem pontuação' do
    expect(numeros(longa, documento: '987.654.321-99')).to eq([1, 2, 160])
    expect(numeros(longa, documento: '98765432199')).to eq([1, 2, 160])
  end

  it 'com o nome, escolhe as páginas em que ele aparece, sem contar caixa, acento e espaço' do
    expect(numeros(longa, nome: 'renata  AMOSTRA límã')).to eq([1, 2, 160])
  end

  it 'o documento vale mais que o nome; se ele não aparece em página nenhuma, vale o nome; sem nenhum, as primeiras' do
    paginas = ['Dados do segurado: Ana Modelo, residente em Cidade Exemplo', 'Documento do segurado: CPF 111.222.333-00, conforme cadastro',
               'Anexo de cobrança em nome de Ana Modelo, débito em conta', 'Condições gerais do seguro, sem dado de segurado nenhum']

    com_pdf(paginas) do |caminho|
      expect(numeros(caminho, documento: '111.222.333-00', nome: 'Ana Modelo')).to eq([2])
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

  it 'arquivo que não é PDF, ou que o leitor de PDF não entende, é ilegível' do
    ['texto puro', '%PDF-1.4 e depois lixo'].each do |conteudo|
      Tempfile.create(['arquivo', '.pdf']) do |arquivo|
        arquivo.write(conteudo)
        arquivo.flush

        expect { described_class.new(arquivo.path).escolhidas }.to raise_error(described_class::Ilegivel)
      end
    end
  end
end
