require 'rails_helper'

RSpec.describe CampaignImports::LabelPlanner do
  def plan_for(total_rows, batch_count)
    account, user = create_account_and_user
    campaign_import = account.campaign_imports.create!(
      user: user, status: :uploaded, mode: 'batches', campaign_name: 'Campanha Ágil', batch_count: batch_count
    )
    described_class.new(campaign_import, total_rows: total_rows).perform
  end

  it 'creates hidden-safe base and batch label plans spread as evenly as possible' do
    plan = plan_for(10, 3)

    expect(plan.base_label).to match(/\Acampanha_campanha_agil_\d+\z/)
    expect(plan.batch_sizes).to eq([4, 3, 3])
  end

  it 'never plans an empty or negative batch (9 rows in 4 batches, 5 rows in 4 batches)' do
    expect(plan_for(9, 4).batch_sizes).to eq([3, 2, 2, 2])
    expect(plan_for(5, 4).batch_sizes).to eq([2, 1, 1, 1])
  end

  it 'keeps every batch positive and the sum exact for 1..50 rows and 1..10 batches' do
    account, user = create_account_and_user
    (1..50).each do |rows|
      (1..[10, rows].min).each do |batches|
        campaign_import = account.campaign_imports.create!(user: user, status: :uploaded, mode: 'batches', batch_count: batches)
        sizes = described_class.new(campaign_import, total_rows: rows).send(:batch_sizes)

        expect(sizes.size).to eq(batches)
        expect(sizes).to all(be_positive)
        expect(sizes.sum).to eq(rows)
      end
    end
  end
end
