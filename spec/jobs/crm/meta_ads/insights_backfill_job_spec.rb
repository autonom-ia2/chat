require 'rails_helper'

# Carga de 90 dias por relatório assíncrono (#1073): pede, confere, lê, segue para o posicionamento.
RSpec.describe Crm::MetaAds::InsightsBackfillJob do
  include_context 'with a meta ads insights connection'

  let(:report_id) { '6123456789' }

  def stub_report_start(kind)
    fields = kind == 'ads' ? Crm::MetaAds::Insights::Query::AD_FIELDS : Crm::MetaAds::Insights::Query::PLACEMENT_FIELDS
    stub_request(:post, meta_graph_url("act_#{ad_account_id}/insights"))
      .with(body: hash_including('date_preset' => 'last_90d', 'level' => 'ad', 'time_increment' => '1', 'fields' => fields))
      .to_return(status: 200, body: { report_run_id: report_id }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_report_status(status)
    stub_request(:get, meta_graph_url(report_id)).with(query: hash_including({}))
                                                 .to_return(status: 200, body: { id: report_id, async_status: status }.to_json,
                                                            headers: { 'Content-Type' => 'application/json' })
  end

  def stub_report_rows(rows)
    stub_request(:get, meta_graph_url("#{report_id}/insights")).with(query: hash_including({}))
                                                               .to_return(status: 200, body: { data: rows }.to_json,
                                                                          headers: { 'Content-Type' => 'application/json' })
  end

  it 'start: uma carga por conexão de cada vez' do
    expect(described_class.start(connection)).to be(true)
    expect(described_class.start(connection)).to be(false)
  end

  it 'pede o relatório de 90 dias e volta para conferir' do
    stub_report_start('ads')

    expect { described_class.perform_now(connection.id) }
      .to have_enqueued_job(described_class).with(connection.id, 'ads', report_id, 0)
  end

  it 'relatório em andamento: confere de novo, até o limite de tentativas' do
    stub_report_status('Job Running')

    expect { described_class.perform_now(connection.id, 'ads', report_id, 3) }
      .to have_enqueued_job(described_class).with(connection.id, 'ads', report_id, 4)
    Crm::MetaAds::Insights::Backfill.claim(connection.id)
    expect { described_class.perform_now(connection.id, 'ads', report_id, described_class::MAX_POLLS) }
      .not_to have_enqueued_job(described_class)
    expect(Crm::MetaAds::Insights::Backfill.claim(connection.id)).to be(true)
  end

  it 'relatório pronto: grava os 90 dias, marca a carga, avisa a tela e segue para o posicionamento' do
    create(:user, account: account, role: :administrator)
    stub_report_status('Job Completed')
    stub_report_rows([meta_insights_row(date: '2026-08-01'), meta_insights_row(date: '2026-08-02')])

    expect { described_class.perform_now(connection.id, 'ads', report_id, 1) }
      .to have_enqueued_job(described_class).with(connection.id, 'placements')
      .and have_enqueued_job(ActionCableBroadcastJob)
    expect(Crm::MetaAdInsightDaily.count).to eq(2)
    expect(connection.reload.insights_backfilled_at).to be_present
  end

  it 'posicionamento pronto: grava e solta a marca' do
    Crm::MetaAds::Insights::Backfill.claim(connection.id)
    stub_report_status('Job Completed')
    stub_report_rows([meta_insights_row(publisher_platform: 'facebook', platform_position: 'feed')])

    expect { described_class.perform_now(connection.id, 'placements', report_id, 0) }.not_to have_enqueued_job(described_class)
    expect(Crm::MetaAdPlacementDaily.count).to eq(1)
    expect(Crm::MetaAds::Insights::Backfill.claim(connection.id)).to be(true)
  end

  it 'relatório que falhou solta a marca sem marcar a carga' do
    Crm::MetaAds::Insights::Backfill.claim(connection.id)
    stub_report_status('Job Failed')

    described_class.perform_now(connection.id, 'ads', report_id, 0)

    expect(connection.reload.insights_backfilled_at).to be_nil
    expect(Crm::MetaAds::Insights::Backfill.claim(connection.id)).to be(true)
  end
end
