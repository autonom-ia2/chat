require 'rails_helper'
require 'roo'

# Arquivos da exportação (#682, frente A): CSV com BOM e ponto e vírgula, Excel mínimo que abre. Os dois neutralizam o
# texto que começa como fórmula: o CSV com o apóstrofo, o Excel com o estilo quotePrefix, sem mexer no texto.
RSpec.describe Autonomia::Prospecting::Export do
  let(:cell) { Autonomia::Prospecting::Export::Cell }
  let(:rows) do
    [
      %w[Nome Nota Telefone],
      ['=HYPERLINK("http://x")', 87.5, '+55 41 99999-0001'],
      ["@SOMA(A1)\tfim", -25.4284, "-1\rx"],
      ['Padaria & Cia <Centro> "boa"', 3, '|cmd'],
      ['Clínica São João', nil, '%total']
    ]
  end

  def read_xlsx(binary)
    Tempfile.create(['export', '.xlsx'], binmode: true) do |file|
      file.write(binary)
      file.flush
      sheet = Roo::Excelx.new(file.path).sheet(0)
      (1..sheet.last_row).map { |index| sheet.row(index) }
    end
  end

  describe Autonomia::Prospecting::Export::Cell do
    it 'prefixa com apóstrofo o texto que começa com =, +, -, @, %, |, tab ou CR' do
      ['=1+1', '+55', '-2', '@x', '%y', '|z', "\tw", "\rv"].each do |value|
        expect(cell.safe(value)).to eq("'#{value}")
      end
    end

    it 'mantém texto comum e número, inclusive número negativo' do
      expect(cell.safe('Padaria')).to eq('Padaria')
      expect(cell.safe(-25.4)).to eq(-25.4)
      expect(cell.safe(nil)).to be_nil
    end
  end

  describe Autonomia::Prospecting::Export::CsvFile do
    subject(:csv) { described_class.generate(rows) }

    it 'começa com o BOM UTF-8 e separa por ponto e vírgula' do
      expect(csv.bytes.first(3)).to eq([0xEF, 0xBB, 0xBF])
      expect(csv.delete_prefix(described_class::BOM).lines.first.chomp).to eq('Nome;Nota;Telefone')
    end

    it 'neutraliza fórmula e escreve decimal com vírgula' do
      parsed = CSV.parse(csv.delete_prefix(described_class::BOM), col_sep: ';')

      expect(parsed[1]).to eq(["'=HYPERLINK(\"http://x\")", '87,5', "'+55 41 99999-0001"])
      expect(parsed[2]).to eq(["'@SOMA(A1)\tfim", '-25,4284', "'-1\rx"])
      expect(parsed[3]).to eq(['Padaria & Cia <Centro> "boa"', '3', "'|cmd"])
      expect(parsed[4]).to eq(['Clínica São João', nil, "'%total"])
    end
  end

  describe Autonomia::Prospecting::Export::XlsxFile do
    subject(:xlsx) { described_class.generate(rows) }

    def xml_part(binary, name)
      Nokogiri::XML(Zip::File.open_buffer(StringIO.new(binary)).read(name))
    end

    def sheet_cell(binary, ref)
      xml_part(binary, 'xl/worksheets/sheet1.xml').at_xpath(%(//xmlns:c[@r="#{ref}"]))
    end

    # Índice, em cellXfs, do estilo com quotePrefix.
    def quoted_style_index(binary)
      xml_part(binary, 'xl/styles.xml').xpath('//xmlns:cellXfs/xmlns:xf').index { |xf| %w[1 true].include?(xf['quotePrefix']) }
    end

    # O CR solto no XML vira quebra de linha (LF) em todo leitor, o Excel inclusive; o resto do texto fica como veio.
    it 'abre como planilha e devolve o texto como foi escrito, sem o apóstrofo do CSV (telefone +55 limpo)' do
      read = read_xlsx(xlsx)

      expect(read[0]).to eq(%w[Nome Nota Telefone])
      expect(read[1]).to eq(['=HYPERLINK("http://x")', 87.5, '+55 41 99999-0001'])
      expect(read[2]).to eq(["@SOMA(A1)\tfim", -25.4284, "-1\nx"])
      expect(read[3]).to eq(['Padaria & Cia <Centro> "boa"', 3, '|cmd'])
      expect(read[4]).to eq(['Clínica São João', nil, '%total'])
    end

    it 'o pacote passa na validação do schema do formato, com e sem linhas' do
      expect(described_class.package(rows).validate).to be_empty
      expect(described_class.package(rows.first(1)).validate).to be_empty
    end

    it 'não grava fórmula: a célula que começa com "=" sai como texto, com o estilo quotePrefix' do
      hyperlink = sheet_cell(xlsx, 'A2')

      expect(xml_part(xlsx, 'xl/worksheets/sheet1.xml').xpath('//xmlns:f')).to be_empty
      expect(hyperlink['t']).to eq('inlineStr')
      expect(hyperlink.text).to eq('=HYPERLINK("http://x")')
      expect(hyperlink['s'].to_i).to eq(quoted_style_index(xlsx))
    end

    it 'só o texto que começa como fórmula leva o quotePrefix, e número vai como número' do
      quoted = quoted_style_index(xlsx)

      expect(quoted).to be_present
      %w[A2 C2 A3 C3 C4 C5].each { |ref| expect(sheet_cell(xlsx, ref)['s'].to_i).to eq(quoted) }
      %w[A4 A5 B2 B3 B4].each { |ref| expect(sheet_cell(xlsx, ref)['s'].to_i).not_to eq(quoted) }
      expect(sheet_cell(xlsx, 'B3')['t']).to eq('n')
      expect(sheet_cell(xlsx, 'B3').text).to eq('-25.4284')
      expect(xlsx).not_to include("'+55")
    end

    it 'filtra pelo cabeçalho com uma tabela do Excel, sem o _FilterDatabase que faz o Excel pedir reparo' do
      table = xml_part(xlsx, 'xl/tables/table1.xml').root
      workbook = Zip::File.open_buffer(StringIO.new(xlsx)).read('xl/workbook.xml')

      expect(table['ref']).to eq('A1:C5')
      expect(workbook).not_to include('_xlnm._FilterDatabase')
    end

    it 'descarta caractere de controle que o XML não aceita, sem perder o resto do texto' do
      read = read_xlsx(described_class.generate([["Nome\u0001 com \u0008controle"]]))

      expect(read[0]).to eq(['Nome com controle'])
    end
  end
end
