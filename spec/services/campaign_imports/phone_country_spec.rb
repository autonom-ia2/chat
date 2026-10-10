require 'rails_helper'

RSpec.describe CampaignImports::PhoneCountry, :aggregate_failures do
  def jev(value: 'brazil', confidence: 0.9, column: 1, schema: 0.95)
    { 'status' => 'answered', 'schema_probability' => schema,
      'phone_country' => { 'value' => value, 'confidence' => confidence, 'column' => column } }
  end

  it 'allows the ninth digit only for brazil, with confidence, for the column Jev judged' do
    expect(described_class.new(jev, 1).brazil?).to be(true)
    expect(described_class.new(jev(confidence: 0.79), 1).brazil?).to be(false)
    expect(described_class.new(jev(value: 'other'), 1).brazil?).to be(false)
    expect(described_class.new(jev(value: 'unknown'), 1).brazil?).to be(false)
    expect(described_class.new(jev, 2).brazil?).to be(false)
    expect(described_class.new(jev, nil).brazil?).to be(false)
    expect(described_class.new(jev(schema: 0.4), 1).brazil?).to be(false)
    expect(described_class.new({ 'status' => 'failed' }, 1).brazil?).to be(false)
  end

  it 'keeps the answer of the reading Jev did after a manual choice, only for the same column' do
    manual = { 'method' => 'manual', 'jev' => { 'status' => 'skipped' } }

    expect(described_class.from(manual, { 'jev' => jev }, 1).brazil?).to be(true)
    expect(described_class.from(manual, { 'jev' => jev }, 2).brazil?).to be(false)
    expect(described_class.from({ 'method' => 'jev', 'jev' => jev }, {}, 1).brazil?).to be(true)
  end

  it 'counts the rows that got the ninth digit and the ones left out' do
    rows = [
      { errors: [], ninth_digit_added: true, legacy_mobile_refused: false },
      { errors: ['duplicate_phone_in_file'], ninth_digit_added: true, legacy_mobile_refused: false },
      { errors: ['invalid_brazilian_mobile_number'], ninth_digit_added: false, legacy_mobile_refused: true }
    ]

    expect(described_class.new(jev(value: 'other'), 1).summary(rows))
      .to eq(phone_country: 'other', ninth_digit_added: 1, legacy_mobiles_refused: 1)
    expect(described_class.new({}, 1).summary([])).to include(phone_country: 'not_answered')
  end
end
