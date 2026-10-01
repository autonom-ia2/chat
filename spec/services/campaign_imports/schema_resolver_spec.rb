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

  it 'prefers the stronger recipient base over a named example when name is optional' do
    content = build_xlsx_sheets(
      'Exemplo' => [%w[NOME EMAIL], ['Exemplo', 'exemplo@example.org']],
      'BASE' => [['EMAIL'], ['ana@example.org'], ['bia@example.org']]
    )
    parsed = CampaignImports::Parser.new(StringIO.new(content), filename: 'base.xlsx').perform

    result = described_class.new(parsed).perform

    expect(result.rows.size).to eq(2)
    expect(result.mapper.mapping).to eq(email: 0)
    expect(result.metadata).to include('table_index' => 1)
  end

  it 'uses Jev with representative examples for unknown columns' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("SEGURADO;MAIL PRINCIPAL;BROKER\nAna;ana@example.org;ABC\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    allow(ai_resolver).to receive(:resolve) do |candidate|
      expect(candidate[:headers]).to eq(['SEGURADO', 'MAIL PRINCIPAL', 'BROKER'])
      expect(candidate.fetch(:profiles)[0][:examples]).to eq(['Aaa'])
      expect(candidate.fetch(:profiles)[1][:examples]).to eq(['[email address]'])
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

  it 'keeps the actual unknown header and never passes invalid recipient names as column labels to Jev' do
    rows = (1..60).map { |index| "Pessoa #{index};invalido-#{index};ABC" } +
           (61..120).map { |index| "Pessoa #{index};pessoa#{index}@example.org;ABC" }
    parsed = CampaignImports::Parser.new(
      StringIO.new("SEGURADO;MAIL PRINCIPAL;BROKER\n#{rows.join("\n")}\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    allow(ai_resolver).to receive(:resolve) do |candidate|
      expect(candidate.fetch(:headers)).to eq(['SEGURADO', 'MAIL PRINCIPAL', 'BROKER'])
      { email_index: 1, name_index: 0, metadata: {} }
    end

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform

    expect(result.rows.length).to eq(120)
    expect(result.metadata['header_row']).to eq(1)
  end

  it 'lets configured Jev interpret even recognized columns before applying local aliases' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("NOME;E-MAIL;CORRETORA\nAna;ana@example.org;ABC\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve).and_return(email_index: 1, name_index: 0, metadata: {})

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform

    expect(result.metadata['method']).to eq('jev')
    expect(result.mapper.mapping).to eq(email: 1, name: 0)
  end

  it 'reports an entirely invalid address list without spending a model call' do
    parsed = CampaignImports::Parser.new(StringIO.new("Nome,Email\nAna,sem-email\nBia,tambem-invalido\n"), filename: 'base.csv').perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).not_to receive(:resolve)

    expect { described_class.new(parsed, ai_resolver: ai_resolver).perform }.to raise_error(described_class::Error, 'no_valid_emails')
  end

  it 'includes real address evidence when the only valid row is outside the initial profile sample' do
    rows = Array.new(120) { |index| "Pessoa #{index},sem-email-#{index}" }
    rows[1] = 'Pessoa válida,valida@example.org'
    parsed = CampaignImports::Parser.new(StringIO.new("Nome,Email\n#{rows.join("\n")}\n"), filename: 'base.csv').perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve) do |candidate|
      expect(candidate.fetch(:profiles)[1].fetch(:total_valid_emails)).to eq(1)
      { email_index: 1, name_index: 0, metadata: {} }
    end

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform
    expect(result.rows.size).to eq(120)
  end

  it 'keeps per-column evidence when another column contains addresses in every sampled row' do
    rows = Array.new(120) { |index| "Pessoa #{index},sem-email-#{index},nota#{index}@example.org" }
    rows[1] = 'Pessoa válida,valida@example.org,nota1@example.org'
    parsed = CampaignImports::Parser.new(StringIO.new("Nome,Email,Nota\n#{rows.join("\n")}\n"), filename: 'base.csv').perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve) do |candidate|
      expect(candidate.fetch(:profiles)[1]).to include(total_valid_emails: 1, email_like_count: 0)
      expect(candidate.fetch(:profiles)[2]).to include(total_valid_emails: 120)
      { email_index: 1, name_index: 0, metadata: {} }
    end

    expect(described_class.new(parsed, ai_resolver: ai_resolver).perform.rows.size).to eq(120)
  end

  it 'sends only character shapes for names, phones and notes, never raw row values' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("Nome,Email,Telefone,Nota\nAna Pessoa,ana@example.org,+55 (11) 98765-4321,Informação pessoal confidencial\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve) do |candidate|
      examples = candidate.fetch(:profiles).map { |profile| profile.fetch(:examples) }
      expect(examples[0]).to eq(['Aaa Aaaaaa'])
      expect(examples[2]).to eq(['+00 (00) 00000-0000'])
      expect(candidate.to_json).not_to include('Ana Pessoa', 'ana@example.org', '98765', 'confidencial')
      { email_index: 1, name_index: 0, metadata: {} }
    end

    described_class.new(parsed, ai_resolver: ai_resolver).perform
  end

  it 'masks malformed addresses while retaining examples for meaningful column identification' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("Nome,Email,Empresa\nAna,ana@example.org,Atlas\nBia,bia@@example.org,Orion\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve) do |candidate|
      expect(candidate.fetch(:profiles)[1][:examples]).to eq(['[email address]', '[malformed email address]'])
      expect(candidate.fetch(:profiles)[2][:examples]).to eq(%w[Aaaaa Aaaaa])
      { email_index: 1, name_index: 0, metadata: {} }
    end

    described_class.new(parsed, ai_resolver: ai_resolver).perform
  end

  it 'lets Jev distinguish a primary recipient address despite duplicate aliases' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("NOME;EMAIL;E-MAIL PRINCIPAL\nAna;ana@example.org;ana.other@example.org\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve).and_return(email_index: 2, name_index: 0, metadata: {})

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform
    expect(result.mapper.mapping).to eq(email: 2, name: 0)
    expect(result.mapper.extra_columns).to eq('email' => 1)
  end

  it 'resolves company versus contact names instead of rejecting before Jev' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("Cliente;Contato;E-mail;Lista\nEmpresa Alfa;Ana Pessoa;ana@example.org;Base\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve).with(hash_including(headers: %w[Cliente Contato E-mail Lista]))
                                            .and_return(email_index: 2, name_index: 1, metadata: {})

    result = described_class.new(parsed, ai_resolver: ai_resolver).perform
    expect(result.mapper.mapping).to eq(email: 2, name: 1)
    expect(result.mapper.extra_columns).to eq('cliente' => 0, 'lista' => 3)
  end

  it 'preserves a safe failure when the model cannot resolve genuine ambiguity' do
    parsed = CampaignImports::Parser.new(
      StringIO.new("Contato;Endereço A;Endereço B\nAna;ana@example.org;bia@example.org\n"), filename: 'base.csv'
    ).perform
    ai_resolver = instance_double(TypesafeAi::ImportSchemaResolver)
    expect(ai_resolver).to receive(:resolve).and_raise(TypesafeAi::ImportSchemaResolver::Error, 'schema_not_resolved')

    expect { described_class.new(parsed, ai_resolver: ai_resolver).perform }.to raise_error(described_class::Error, 'schema_not_resolved')
  end

  it 'fails with a specific missing-email code when neither deterministic mapping nor Jev is available' do
    parsed = CampaignImports::Parser.new(StringIO.new("SEGURADO;BROKER\nAna;ABC\n"), filename: 'base.csv').perform
    allow(TypesafeAi::Config).to receive(:enabled?).and_return(false)

    expect { described_class.new(parsed).perform }.to raise_error(described_class::Error, 'missing_email_header')
  end
end
