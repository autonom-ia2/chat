require 'rails_helper'

# Leitura síncrona de insights (#1073): hoje, os 3 dias anteriores com posicionamento, e o que fazer quando a
# Meta recusa (CA-2.1, CA-2.2, CA-2.6).
RSpec.describe Crm::MetaAds::Insights::Sync do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_account_id) { connection.ad_account_id }
  let(:sync) { described_class.new(connection) }

  after { Redis::Alfred.delete(Crm::MetaAds::Insights::Usage.key(ad_account_id)) }

  it 'hoje: uma chamada por conta de anúncios, nível anúncio, dia a dia, janela fixa e sem ids (CA-2.1)' do
    graph = stub_meta_insights(ad_account_id, date_preset: 'today', rows: [meta_insights_row])

    expect(sync.perform('today')).to eq(:ok)

    expect(graph.with(query: hash_including('action_attribution_windows' => '["7d_click"]', 'limit' => '500'))).to have_been_requested.once
    expect(a_request(:get, /ids=/)).not_to have_been_made
    expect(Crm::MetaAdInsightDaily.sole.spend).to eq(BigDecimal('42.5'))
    expect(connection.reload.insights_synced_at).to be_present
  end

  it 'conexão feita antes da F2a aprende o fuso da conta de anúncios uma vez' do
    connection.update!(ad_account_timezone: nil)
    account_read = stub_request(:get, meta_graph_url("act_#{ad_account_id}"))
                   .with(query: hash_including('fields' => Meta::AdsGraphClient::AD_ACCOUNT_FIELDS))
                   .to_return(status: 200, body: { id: "act_#{ad_account_id}", timezone_name: 'America/Sao_Paulo' }.to_json,
                              headers: { 'Content-Type' => 'application/json' })
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: [])

    sync.perform('today')
    described_class.new(connection.reload).perform('today')

    expect(connection.ad_account_timezone).to eq('America/Sao_Paulo')
    expect(account_read).to have_been_requested.once
  end

  it 'segue as páginas da Meta pelo cursor' do
    first = { data: [meta_insights_row], paging: { cursors: { after: 'CUR1' }, next: 'https://graph.facebook.com/next' } }
    stub_request(:get, meta_graph_url("act_#{ad_account_id}/insights"))
      .with(query: hash_including('date_preset' => 'today'))
      .to_return(status: 200, body: first.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, meta_graph_url("act_#{ad_account_id}/insights"))
      .with(query: hash_including('date_preset' => 'today', 'after' => 'CUR1'))
      .to_return(status: 200, body: { data: [meta_insights_row(ad_id: '777777')] }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(sync.perform('today')).to eq(:ok)
    expect(Crm::MetaAdInsightDaily.pluck(:ad_id)).to contain_exactly('120254710067060999', '777777')
  end

  it 'recentes: os 3 dias anteriores por anúncio e por posicionamento, sem mexer na hora da leitura de hoje' do
    stub_meta_insights(ad_account_id, date_preset: 'last_3d', rows: [meta_insights_row(date: '2026-10-04')])
    placements = stub_meta_insights(ad_account_id, date_preset: 'last_3d', breakdowns: 'publisher_platform,platform_position',
                                                   rows: [meta_insights_row(publisher_platform: 'instagram', platform_position: 'story')])

    expect(sync.perform('recent')).to eq(:ok)

    expect(placements).to have_been_requested.once
    expect(Crm::MetaAdInsightDaily.sole.date).to eq(Date.new(2026, 10, 4))
    expect(Crm::MetaAdPlacementDaily.sole.platform_position).to eq('story')
    expect(connection.reload.insights_synced_at).to be_nil
  end

  it 'uso acima de 75% pausa a conta de anúncios e a próxima leitura nem chama a Meta (CA-2.2)' do
    allow(Rails.logger).to receive(:warn)
    usage = { 'x-fb-ads-insights-throttle' => { app_id_util_pct: 10, acc_id_util_pct: 90 }.to_json }
    graph = stub_meta_insights(ad_account_id, date_preset: 'today', rows: [meta_insights_row], headers: usage)

    expect(sync.perform('today')).to eq(:ok)
    expect(described_class.new(connection).perform('today')).to eq(:paused)
    expect(graph).to have_been_requested.once
  end

  it 'limite estourado não marca a conexão como inválida (CA-2.2)' do
    allow(Rails.logger).to receive(:warn)
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: meta_graph_error(17, 'User request limit reached'), status: 400)

    expect(sync.perform('today')).to eq(:paused)
    expect(connection.reload).to have_attributes(status: 'active', last_error: nil, insights_synced_at: nil)
  end

  it 'conta de anúncios sem acesso para de ser lida, com o motivo (CA-2.6)' do
    allow(Rails.logger).to receive(:warn)
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: meta_graph_error(100, 'Object does not exist'), status: 400)

    expect(sync.perform('today')).to eq(:access_lost)
    expect(connection.reload).to have_attributes(status: 'invalid', last_error: 'ad_account_access_lost')
    expect(described_class.new(connection).perform('today')).to eq(:skipped)
  end

  it 'token recusado segue a regra das outras leituras' do
    allow(Rails.logger).to receive(:warn)
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: meta_graph_error(190, 'Session expired'), status: 400)

    expect(sync.perform('today')).to eq(:token_invalid)
    expect(connection.reload.status).to eq('invalid')
  end

  it 'falha passageira não muda a conexão' do
    allow(Rails.logger).to receive(:warn)
    stub_meta_insights(ad_account_id, date_preset: 'today', rows: meta_graph_error(2, 'Service temporarily unavailable'), status: 500)

    expect(sync.perform('today')).to eq(:transient)
    expect(connection.reload).to have_attributes(status: 'active', last_error: nil)
  end

  it 'conexão sem conta de anúncios não chama a Meta' do
    connection.update!(ad_account_id: nil)

    expect(sync.perform('today')).to eq(:skipped)
  end
end
