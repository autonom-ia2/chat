require 'rails_helper'

RSpec.describe CampaignImports::SpreadsheetReader, :aggregate_failures do
  def parsed(content, filename: 'base.csv')
    CampaignImports::Parser.new(StringIO.new(content), filename: filename).perform
  end

  def jev(targets, schema: 0.99)
    resolver = instance_double(TypesafeAi::AudienceSchemaResolver)
    allow(resolver).to receive(:resolve).and_return(targets: targets, schema_probability: schema, model: 'jev-1.13.0')
    resolver
  end

  let(:content) { "Nome,Celular,Email,Plano,,Plano\nAna,11987654321,ana@x.com.br,Ouro,,Anual\n" }

  it 'needs confirmation when Jev picks the same column for two targets' do
    resolver = jev({ name: { index: 0, confidence: 0.9 }, phone: { index: 1, confidence: 0.9 },
                     email: { index: 2, confidence: 0.9 }, company: { index: 0, confidence: 0.9 } })

    result = described_class.new(parsed(content), ai_resolver: resolver, jev_enabled: true).perform

    expect(result).to be_needs_column_choice
    expect(result.resolution['uncertain_targets']).to match_array(%w[name company])
    expect(result.resolution['targets']['name']).to include('column' => 0, 'source' => 'alias')
  end

  it 'does not trust a phone column without any valid mobile number' do
    resolver = jev({ name: { index: 0, confidence: 0.9 }, phone: { index: 3, confidence: 0.99 },
                     email: { index: 2, confidence: 0.9 }, company: { index: nil, confidence: 0.9 } })

    result = described_class.new(parsed(content), ai_resolver: resolver, jev_enabled: true).perform

    expect(result.resolution['uncertain_targets']).to eq(['phone'])
    expect(result.resolution['targets']['phone']).to include('column' => 1, 'source' => 'alias', 'confident' => false)
  end

  it 'keeps every unbound column as an extra column with a unique key' do
    resolver = jev({ name: { index: 0, confidence: 0.9 }, phone: { index: 1, confidence: 0.9 },
                     email: { index: 2, confidence: 0.9 }, company: { index: nil, confidence: 0.9 } })

    result = described_class.new(parsed(content), ai_resolver: resolver, jev_enabled: true).perform

    expect(result).not_to be_needs_column_choice
    expect(result.resolution['method']).to eq('jev')
    expect(result.extra_columns).to eq([{ 'index' => 3, 'key' => 'Plano' }, { 'index' => 5, 'key' => 'Plano (2)' }])
  end

  it 'never calls Jev when the journey switch is off' do
    resolver = instance_double(TypesafeAi::AudienceSchemaResolver)
    allow(resolver).to receive(:resolve)

    result = described_class.new(parsed(content), ai_resolver: resolver, jev_enabled: false).perform

    expect(resolver).not_to have_received(:resolve)
    expect(result.resolution).to include('method' => 'deterministic', 'needs_confirmation' => true)
  end

  it 'refuses a manual choice without a phone or email column' do
    expect do
      described_class.new(parsed(content), explicit_mapping: { 'name' => 0, 'company' => 3 },
                                           pinned_header: { header_row: 1, table_index: 0 }).perform
    end.to raise_error(described_class::Error, 'missing_contact_column')
  end
end
