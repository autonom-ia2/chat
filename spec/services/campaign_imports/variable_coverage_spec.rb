require 'rails_helper'

RSpec.describe CampaignImports::VariableCoverage, :aggregate_failures do
  let(:campaign_import) do
    account, user = create_account_and_user
    import = create_audience_import(
      account: account, user: user,
      content: "Segurado,Fone 1,Corretora,Vencimento\nAna,11987654321,Alfa,10/2026\nBia,21987654321,Beta,\nCaio,31987654321,,11/2026\n"
    )
    import.update!(schema_resolution: { 'manual_mapping' => { 'name' => 0, 'phone' => 1, 'company' => 2 }, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(import).perform
    import.reload
  end
  let(:mapping) { { '1' => { 'source' => 'name' }, '2' => { 'source' => 'extra', 'column' => 'Vencimento' } } }

  # B1b: a valid row without a value for a used variable stays out with the reason, unless a default text was chosen.
  it 'leaves out rows missing a used variable and says which variable' do
    result = described_class.new(campaign_import, mapping: mapping).perform

    expect(result.included_count).to eq(2)
    expect(result.excluded).to eq([{ row_number: 3, missing: ['2'] }])
    expect(result.missing_by_variable).to eq('2' => 1)
  end

  it 'keeps every row when a default text covers the missing value' do
    result = described_class.new(campaign_import, mapping: mapping, defaults: { '2' => 'em breve' }).perform

    expect(result.included_count).to eq(3)
    expect(result.excluded_count).to eq(0)
  end

  it 'checks the company column too' do
    result = described_class.new(campaign_import, mapping: { '3' => { 'source' => 'company' } }).perform

    expect(result.excluded).to eq([{ row_number: 4, missing: ['3'] }])
  end

  it 'refuses a column that is not in the audience' do
    expect do
      described_class.new(campaign_import, mapping: { '2' => { 'source' => 'extra', 'column' => 'CPF' } }).perform
    end.to raise_error(described_class::Error, 'invalid_variable_mapping')
  end
end
