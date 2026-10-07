require 'rails_helper'

# O descanso da escala (#1110, F5, §1.3): aumento aceito fica SCALE_COOLDOWN_DAYS dias sem escalar de novo, hoje
# incluído. Com 5 dias (o limite de cima do PRD, "3 a 5 dias"), o aumento não se repete antes de haver dado novo.
RSpec.describe Crm::MetaAds::Advisor::History do
  let(:account) { create(:account) }
  let(:today) { Date.new(2026, 10, 7) }

  def accept_scale(ad_id, local_date)
    advisor_resolved(account, kind: 'scale_ad', subject_key: "ad:#{ad_id}", status: :accepted, local_date: local_date)
  end

  it 'aceito há 4 dias ainda está em descanso; há 5 dias, não' do
    accept_scale('A', today - 4)
    accept_scale('B', today - 5)

    expect(described_class.for(account.id, today)).to eq(scale_accepted_ad_ids: ['A'])
  end
end
