require 'rails_helper'

RSpec.describe CampaignImports::Parser do
  it 'parses comma CSV files' do
    content = "nome,telefone\nAna,11987654321\n"
    parsed = described_class.new(StringIO.new(content), filename: 'base.csv').perform

    expect(parsed.headers).to eq(%w[nome telefone])
    expect(parsed.rows.first.values).to eq(%w[Ana 11987654321])
    expect(parsed.tables.first.delimiter).to eq(',')
  end

  it 'detects semicolon, tab and pipe-delimited CSV files' do
    cases = [
      [';', "NOME;E-MAIL;CORRETORA\nAna;ana@example.org;ABC\n"],
      ["\t", "NOME\tE-MAIL\tCORRETORA\nAna\tana@example.org\tABC\n"],
      ['|', "NOME|E-MAIL|CORRETORA\nAna|ana@example.org|ABC\n"]
    ]

    cases.each do |delimiter, content|
      parsed = described_class.new(StringIO.new(content), filename: 'base.csv').perform
      expect(parsed.headers).to eq(['NOME', 'E-MAIL', 'CORRETORA'])
      expect(parsed.rows.first.values).to eq(['Ana', 'ana@example.org', 'ABC'])
      expect(parsed.tables.first.delimiter).to eq(delimiter)
    end
  end

  it 'handles the sep marker emitted by some spreadsheet exports' do
    content = "sep=;\nNOME;E-MAIL;CORRETORA\nAna;ana@example.org;ABC\n"
    parsed = described_class.new(StringIO.new(content), filename: 'base.csv').perform

    expect(parsed.tables.first.delimiter).to eq(';')
    expect(parsed.tables.first.rows[1].values).to eq(['NOME', 'E-MAIL', 'CORRETORA'])
  end

  it 'respects quoted delimiters while detecting a semicolon CSV' do
    content = %(NOME;E-MAIL;OBSERVACAO\n"Silva, Ana";ana@example.org;"Cliente; premium"\n)
    parsed = described_class.new(StringIO.new(content), filename: 'base.csv').perform

    expect(parsed.tables.first.delimiter).to eq(';')
    expect(parsed.rows.first.values).to eq(['Silva, Ana', 'ana@example.org', 'Cliente; premium'])
  end

  it 'removes UTF-8 BOM without changing the first header' do
    parsed = described_class.new(StringIO.new("\uFEFFNOME;E-MAIL\nAna;ana@example.org\n"), filename: 'base.csv').perform

    expect(parsed.headers).to eq(['NOME', 'E-MAIL'])
  end

  it 'transcodes UTF-16LE and UTF-16BE files exported by spreadsheet tools' do
    text = "NOME\tE-MAIL\tCIDADE\nJoão\tjoao@example.org\tSão Paulo\n"
    cases = [
      ["\xFF\xFE".b, Encoding::UTF_16LE],
      ["\xFE\xFF".b, Encoding::UTF_16BE]
    ]

    cases.each do |bom, encoding|
      source = bom + text.encode(encoding).b
      parsed = described_class.new(StringIO.new(source), filename: 'base.csv').perform

      expect(parsed.tables.first.delimiter).to eq("\t")
      expect(parsed.headers).to eq(['NOME', 'E-MAIL', 'CIDADE'])
      expect(parsed.rows.first.values).to eq(['João', 'joao@example.org', 'São Paulo'])
    end
  end

  it 'transcodes Windows-1252 CSV files to UTF-8' do
    source = "NOME;E-MAIL;CIDADE\nJoão;joao@example.org;São Paulo\n".encode(Encoding::Windows_1252)
    parsed = described_class.new(StringIO.new(source), filename: 'base.csv').perform

    expect(parsed.headers).to eq(['NOME', 'E-MAIL', 'CIDADE'])
    expect(parsed.rows.first.values).to eq(['João', 'joao@example.org', 'São Paulo'])
    expect(parsed.rows.first.values.all?(&:valid_encoding?)).to be(true)
  end

  it 'parses XLSX files' do
    content = build_xlsx([%w[nome telefone], ['Ana', '11987654321']])
    parsed = described_class.new(StringIO.new(content), filename: 'base.xlsx').perform

    expect(parsed.headers).to eq(%w[nome telefone])
    expect(parsed.rows.first.values).to eq(%w[Ana 11987654321])
  end

  it 'exposes every XLSX sheet for schema selection' do
    content = build_xlsx_sheets(
      'Instruções' => [['Leia antes de usar']],
      'Resumo' => [%w[Campo Valor], %w[Total 2]],
      'BASE CLIENTES' => [%w[NOME EMAIL], ['Ana', 'ana@example.org'], ['Bia', 'bia@example.org']]
    )
    parsed = described_class.new(StringIO.new(content), filename: 'base.xlsx').perform

    expect(parsed.tables.map(&:name)).to eq(['Instruções', 'Resumo', 'BASE CLIENTES'])
    expect(parsed.tables.last.rows.first.values).to eq(%w[NOME EMAIL])
    expect(parsed.tables.last.rows.last.values).to eq(['Bia', 'bia@example.org'])
  end

  it 'ignores hidden helper sheets when exposing XLSX tables' do
    content = build_xlsx_sheets_with_hidden(
      {
        'AUXILIAR' => [%w[NOME EMAIL], ['Interno', 'interno@example.org']],
        'BASE CLIENTES' => [%w[NOME EMAIL], ['Ana', 'ana@example.org']]
      },
      hidden: ['AUXILIAR']
    )
    parsed = described_class.new(StringIO.new(content), filename: 'base.xlsx').perform

    expect(parsed.tables.map(&:name)).to eq(['BASE CLIENTES'])
  end

  it 'rejects XLSX files that exceed the uncompressed limit' do
    content = build_xlsx([%w[nome telefone], ['Ana', '11987654321']])

    expect do
      CampaignImports::XlsxReader.new(content, max_uncompressed_bytes: 10).rows
    end.to raise_error(ArgumentError, /xlsx_.*too_large/)
  end
end
