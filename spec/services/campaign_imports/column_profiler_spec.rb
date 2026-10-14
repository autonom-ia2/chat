require 'rails_helper'

RSpec.describe CampaignImports::ColumnProfiler, :aggregate_failures do
  let(:rows) do
    [
      CampaignImports::Parser::ParsedRow.new(row_number: 1, values: %w[Celular Email]),
      CampaignImports::Parser::ParsedRow.new(row_number: 2, values: ['(11) 98765-4321', 'joao@empresa.com.br'])
    ]
  end

  def examples(reveal_area_codes:)
    described_class.new(rows, reveal_area_codes: reveal_area_codes).profiles(2, rows.drop(1), 0).map { |profile| profile[:examples] }
  end

  it 'masks every digit and hides the email in the classic reading' do
    expect(examples(reveal_area_codes: false)).to eq([['(00) 00000-0000'], ['[email address]']])
  end

  it 'keeps the DDD and the email domain visible in the customer_base reading' do
    expect(examples(reveal_area_codes: true)).to eq([['(11) 00000-0000'], ['aaaa@empresa.com.br']])
  end
end
