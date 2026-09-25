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

    it 'abre como planilha e devolve o texto como foi escrito, sem o apóstrofo do CSV (telefone +55 limpo)' do
      read = read_xlsx(xlsx)

      expect(read[0]).to eq(%w[Nome Nota Telefone])
      expect(read[1]).to eq(['=HYPERLINK("http://x")', 87.5, '+55 41 99999-0001'])
      expect(read[2]).to eq(["@SOMA(A1)\tfim", -25.4284, "-1\rx"])
      expect(read[3]).to eq(['Padaria & Cia <Centro> "boa"', 3, '|cmd'])
      expect(read[4]).to eq(['Clínica São João', nil, '%total'])
    end

    it 'tem o estilo quotePrefix e o estilo Normal padrão' do
      styles = Zip::File.open_buffer(StringIO.new(xlsx)).read('xl/styles.xml')

      expect(styles).to include('<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" quotePrefix="1"/>')
      expect(styles).to include('<cellStyle name="Normal" xfId="0" builtinId="0"/>')
    end

    it 'não grava fórmula: todo texto vai como inlineStr, e o que começa como fórmula leva o estilo quotePrefix' do
      sheet = Zip::File.open_buffer(StringIO.new(xlsx)).read('xl/worksheets/sheet1.xml')

      expect(sheet).not_to include('<f>')
      expect(sheet).to include('t="inlineStr"')
      quoted = described_class::QUOTED_STYLE
      %w[A2 C2 A3 C3 C4 C5].each { |ref| expect(sheet).to include(%(<c r="#{ref}" s="#{quoted}" t="inlineStr">)) }
      %w[A4 A5].each { |ref| expect(sheet).to include(%(<c r="#{ref}" t="inlineStr">)) }
      expect(sheet).to include('<c r="B3"><v>-25.4284</v></c>')
      expect(sheet).not_to include("'+55")
    end

    it 'descarta caractere de controle que o XML não aceita, sem perder o resto do texto' do
      read = read_xlsx(described_class.generate([["Nome\u0001 com \u0008controle"]]))

      expect(read[0]).to eq(['Nome com controle'])
    end
  end
end
