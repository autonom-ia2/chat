require 'rails_helper'

# #1004: SMS part counter (contract §4 of api-1004.md). The screen counts with the same rules.
RSpec.describe CampaignJourney::SmsSegments, :aggregate_failures do
  def count(text)
    described_class.count(text)
  end

  it 'counts plain GSM-7 text in one part up to 160 characters' do
    expect(count('a' * 160)).to eq(encoding: 'GSM-7', characters: 160, units: 160, segments: 1, per_segment: 160)
    expect(count('')).to include(segments: 0, units: 0)
  end

  it 'splits longer GSM-7 text in parts of 153' do
    expect(count('a' * 161)).to include(segments: 2, per_segment: 153)
    expect(count('a' * 306)).to include(segments: 2)
    expect(count('a' * 307)).to include(segments: 3)
  end

  it 'counts an extension character as 2 units and never splits it' do
    expect(count('€')).to include(encoding: 'GSM-7', characters: 1, units: 2)
    expect(count("#{'a' * 158}{")).to include(units: 160, segments: 1)
    expect(count("#{'a' * 152}[#{'a' * 152}")).to include(units: 306, segments: 3)
  end

  it 'switches to UCS-2 with a character outside GSM-7 (Portuguese accents like ã, ç)' do
    expect(count('Ola, tudo bem? à')).to include(encoding: 'GSM-7')
    expect(count('Olá')).to include(encoding: 'UCS-2')
    expect(count('Promoção')).to include(encoding: 'UCS-2', segments: 1, per_segment: 70)
    expect(count('ã' * 71)).to include(segments: 2, per_segment: 67)
  end

  it 'counts an emoji outside the basic plane as 2 units without splitting it' do
    expect(count('😀')).to include(encoding: 'UCS-2', characters: 1, units: 2)
    expect(count("#{'a' * 66}😀")).to include(units: 68, segments: 1)
    expect(count("#{'a' * 66}😀#{'a' * 3}")).to include(units: 71, segments: 2)
  end
end
