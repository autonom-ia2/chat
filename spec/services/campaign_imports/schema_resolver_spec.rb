require 'rails_helper'

RSpec.describe CampaignImports::SchemaResolver do
  it 'finds a known recipient header after title rows without AI' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("Relatório de clientes\nGerado em 29/09/2026\n\nNOME;E-MAIL;CORRETORA\nAna;ana@example.org;ABC\n"),
      filename: 'base.csv'
    ).perform

    result = described_class.new(parsed).perform

    expect(result.headers).to eq(%w[NOME E-MAIL CORRETORA])
    expect(result.mapper.mapping).to eq(name: 0, email: 1)
    expect(result.rows.map(&:row_number)).to eq([5])
    expect(result.metadata).to include('method' => 'deterministic', 'header_row' => 4, 'delimiter' => ';')
  end

  it 'chooses the XLSX sheet with the strongest usable recipient data' do
    content = build_xlsx_sheets(
      'Exemplo' => [%w[NOME EMAIL], ['Exemplo', 'exemplo@example.org']],
      'BASE CLIENTES' => [%w[NOME EMAIL CORRETORA], ['Ana', 'ana@example.org', 'ABC'], ['Bia', 'bia@example.org', 'XYZ']]
    )
    parsed = CampaignImports::Parser.new(StringIO.new(content), filename: 'base.xlsx').perform

    result = described_class.new(parsed).perform

    expect(result.rows.size).to eq(2)
    expect(result.rows.first.values).to eq(['Ana', 'ana@example.org', 'ABC'])
    expect(result.metadata).to include('table_index' => 1, 'email_column' => 1)
  end

  it 'samples across a long file instead of requiring the first rows to contain valid emails' do
    invalid_prefix = (1..60).map { |index| "Pessoa #{index},sem-email-#{index}" }.join("\n")
    valid_suffix = (61..120).map { |index| "Pessoa #{index},pessoa#{index}@example.org" }.join("\n")
    parsed = CampaignImports::Parser.new(
      StringIO.new("NOME,EMAIL\n#{invalid_prefix}\n#{valid_suffix}\n"), filename: 'base.csv'
    ).perform

    result = described_class.new(parsed).perform

    expect(result.mapper.mapping).to eq(name: 0, email: 1)
    expect(result.metadata['method']).to eq('deterministic')
  end

  it 'uses Jev only when deterministic aliases cannot resolve the email column' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("SEGURADO;MAIL PRINCIPAL;BROKER\nAna;ana@example.org;ABC\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    allow(ai_resolver).to receive(:resolve) do |candidate|
      expect(candidate[:headers]).to eq(['SEGURADO', 'MAIL PRINCIPAL', 'BROKER'])
      {
        candidate_id: candidate.fetch(:id),
        email_index: 1,
        name_index: 0,
        metadata: { 'model' => 'jev-1.13.0', 'email_confidence' => 0.91 }
      }
    end

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform

    expect(result.mapper.mapping).to eq(email: 1, name: 0)
    expect(result.mapper.extra_columns).to eq('broker' => 2)
    expect(result.metadata).to include('method' => 'jev', 'model' => 'jev-1.13.0')
  end

  it 'does not call Jev when deterministic headers already resolve safely' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("NOME;E-MAIL;CORRETORA\nAna;ana@example.org;ABC\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).not_to receive(:resolve)

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform

    expect(result.metadata['method']).to eq('deterministic')
    expect(result.mapper.mapping).to eq(name: 0, email: 1)
  end

  it 'does not let Jev guess between duplicated semantic email columns' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("NOME;EMAIL;E-MAIL PRINCIPAL\nAna;ana@example.org;ana.other@example.org\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).not_to receive(:resolve)

    expect { described_class.new(parsed, ai_resolver: ai_resolver).perform }
      .to raise_error(described_class::Error, 'duplicated_email_header')
  end

  it 'fails with a specific missing-email code when neither deterministic mapping nor Jev is available' do
    parsed = CampaignImports::Parser.new(StringIO.new("SEGURADO;BROKER\nAna;ABC\n"), filename: 'base.csv').perform
    allow(TypesafeAi::Config).to receive(:enabled?).and_return(false)

    expect { described_class.new(parsed).perform }.to raise_error(described_class::Error, 'missing_email_header')
  end
end
