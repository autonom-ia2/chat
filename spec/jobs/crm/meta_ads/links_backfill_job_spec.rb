require 'rails_helper'

# Carga das ligações dos últimos 90 dias (#1073, F2b): só banco, uma por conexão, avisa a tela no fim.
RSpec.describe Crm::MetaAds::LinksBackfillJob do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ctwa_touch) do
    { 'source' => 'meta_ctwa', 'source_id' => '120254710067060999', 'ctwa_clid' => 'clid-1', 'touched_at' => 2.days.ago.iso8601 }
  end

  after { Redis::Alfred.delete("#{described_class::RUNNING_KEY}:#{connection.id}") }

  it 'start: uma carga por conexão de cada vez' do
    expect(described_class.start(connection)).to be(true)
    expect(described_class.start(connection)).to be(false)
  end

  it 'liga as conversas com toque dos últimos 90 dias, marca a carga, avisa a tela e solta a marca' do
    create(:user, account: account, role: :administrator)
    recent = create(:conversation, account: account, additional_attributes: { 'campaign_touches' => [ctwa_touch] })
    old = create(:conversation, account: account, additional_attributes: { 'campaign_touches' => [ctwa_touch.merge('ctwa_clid' => 'clid-old')] })
    old.update_columns(updated_at: 100.days.ago) # rubocop:disable Rails/SkipsModelValidations
    described_class.start(connection)

    expect { described_class.perform_now(connection.id) }.to have_enqueued_job(ActionCableBroadcastJob)

    expect(Crm::MetaAdLink.pluck(:conversation_id)).to eq([recent.id])
    expect(connection.reload.links_backfilled_at).to be_present
    expect(described_class.start(connection)).to be(true)
  end
end
