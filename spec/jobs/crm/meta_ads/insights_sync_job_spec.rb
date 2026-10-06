require 'rails_helper'

# Leitura de insights (#1073): trava solta no fim e aviso em tempo real só aos administradores.
RSpec.describe Crm::MetaAds::InsightsSyncJob do
  include_context 'with a meta ads insights connection'

  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  it 'lê, avisa só os administradores com o resumo e solta a trava' do
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: [meta_insights_row(date: '2026-10-06', spend: '42.50')])
    Crm::MetaAds::Insights::Refresh.claim(connection.id, 'today')
    admin
    agent

    expect { described_class.perform_now(connection.id, 'today') }
      .to have_enqueued_job(ActionCableBroadcastJob).with(
        [admin.pubsub_token], 'crm.meta_ads.insights_updated',
        hash_including(account_id: account.id, date: Date.new(2026, 10, 6), spend: '42.5', currency: 'BRL', conversations: 3,
                       refreshing: false)
      )
    expect(Crm::MetaAds::Insights::Refresh.running?(connection.id)).to be(false)
  end

  it 'avisa a tela e solta a trava mesmo quando a Meta falha' do
    allow(Rails.logger).to receive(:warn)
    admin
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: meta_graph_error(2, 'Unavailable'), status: 500)
    Crm::MetaAds::Insights::Refresh.claim(connection.id, 'today')

    expect { described_class.perform_now(connection.id, 'today') }.to have_enqueued_job(ActionCableBroadcastJob)
    expect(Crm::MetaAds::Insights::Refresh.running?(connection.id)).to be(false)
  end

  it 'leitura dos 3 dias não avisa a tela' do
    admin
    stub_meta_insights(ad_account_id, date_preset: 'last_3d', rows: [])
    stub_meta_insights(ad_account_id, date_preset: 'last_3d', breakdowns: 'publisher_platform,platform_position', rows: [])

    expect { described_class.perform_now(connection.id, 'recent') }.not_to have_enqueued_job(ActionCableBroadcastJob)
  end
end
