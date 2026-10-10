require 'rails_helper'

RSpec.describe EmailCampaigns::Ai::SubjectVariants do
  it 'keeps the first 3 when more come back' do
    result = described_class.new(%w[a b c d e])

    expect(result.variants).to eq(%w[a b c])
    expect(result.warning).to be_nil
  end

  it 'accepts fewer than 3 and records a warning' do
    result = described_class.new(%w[a b])

    expect(result.variants).to eq(%w[a b])
    expect(result.warning).to eq('check' => 'subject_variants', 'detail' => '2 of 3')
  end

  it 'collapses duplicates and drops blanks before counting' do
    result = described_class.new(['Oferta', ' Oferta ', '', nil, 'Novidade', 'Oferta', 'Última chance', 'Extra'])

    expect(result.variants).to eq(['Oferta', 'Novidade', 'Última chance'])
    expect(result.warning).to be_nil
  end

  it 'reads anything that is not a list as no variants' do
    expect(described_class.new('x').variants).to eq([])
  end
end
