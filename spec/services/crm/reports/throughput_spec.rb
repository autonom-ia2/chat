require 'rails_helper'

RSpec.describe Crm::Reports::Throughput do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:closed_at) { Time.zone.parse('2026-07-04T10:00:00Z') }
  let(:params) { { since: '2026-07-01T00:00:00Z', until: '2026-07-31T23:59:59Z', group_by: 'day' } }

  def close_card(pipeline, stage, status)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: "Assunto #{SecureRandom.hex(3)}", currency: 'BRL')
    travel_to(closed_at) { card.update!(status: status) }
    card
  end

  def throughput_for(pipeline)
    described_class.new(account: account, params: params.merge(pipeline_id: pipeline.id)).perform
  end

  it 'counts each won sale card, two sales in the same day count two' do
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    2.times { close_card(pipeline, stage, :won) }
    close_card(pipeline, stage, :lost)

    expect(throughput_for(pipeline)).to include(
      counts_as_sale: true,
      series: [{ date: '2026-07-04', won: 2, lost: 1, resolved: 0, cancelled: 0 }]
    )
  end

  # #1876: o dia do gráfico é o da conta. Ganho em 31/10 às 22h de São Paulo (01/11 01h UTC) é do dia 31.
  it 'buckets by day in the account timezone' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Tarde', currency: 'BRL')
    travel_to(Time.utc(2026, 11, 1, 1, 0)) { card.update!(status: :won) }
    window = { since: '2026-10-30T03:00:00Z', until: '2026-11-02T03:00:00Z', group_by: 'day', pipeline_id: pipeline.id }

    result = described_class.new(account: account, params: window).perform

    expect(result[:series]).to eq([{ date: '2026-10-31', won: 1, lost: 0, resolved: 0, cancelled: 0 }])
  end

  it 'reports a service funnel as resolved and cancelled, never as won or lost' do
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Sinistros')
    close_card(pipeline, stage, :won)
    pipeline.update!(counts_as_sale: false)
    close_card(pipeline, stage, :resolved)
    close_card(pipeline, stage, :cancelled)

    expect(throughput_for(pipeline)).to include(
      counts_as_sale: false,
      series: [{ date: '2026-07-04', won: 0, lost: 0, resolved: 1, cancelled: 1 }]
    )
  end
end
