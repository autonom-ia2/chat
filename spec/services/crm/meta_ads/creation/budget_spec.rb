require 'rails_helper'

# Orçamento e datas do anúncio (#2198, pontos 5, 10 e 11): lido no grupo ou na campanha, com quantos anúncios estão no ar,
# erro em vez de vazio, e a troca revalidada no servidor (R$ 6 a R$ 500 por dia, fim depois de hoje).
RSpec.describe Crm::MetaAds::Creation::Budget do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_id) { '120000000000216101' }
  let(:adset_id) { '120000000000021611' }
  let(:campaign_id) { '120000000000002161' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_budget(adset: {}, campaign: {}, account_id: connection.ad_account_id, status: 200)
    body = if status == 200
             { id: ad_id, account_id: account_id,
               adset: { id: adset_id, name: 'Público 25-45', start_time: '2026-10-01T09:00:00-0300', effective_status: 'ACTIVE' }.merge(adset),
               campaign: { id: campaign_id, name: 'Vendas', effective_status: 'ACTIVE' }.merge(campaign) }
           else
             meta_graph_error(status == 500 ? 1 : 100)
           end
    stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_BUDGET_FIELDS })
                                             .to_return(status: status, body: body.to_json, headers: json)
  end

  def stub_ads(object_id, statuses)
    body = { data: statuses.map { |status| { effective_status: status } } }
    stub_request(:get, meta_graph_url("#{object_id}/ads")).with(query: hash_including('fields' => 'effective_status'))
                                                          .to_return(status: 200, body: body.to_json, headers: json)
  end

  def stub_currency(currency = 'BRL')
    body = { id: "act_#{connection.ad_account_id}", currency: currency }
    stub_request(:get, meta_graph_url("act_#{connection.ad_account_id}")).with(query: hash_including({}))
                                                                         .to_return(status: 200, body: body.to_json, headers: json)
  end

  before do
    travel_to Time.zone.parse('2026-10-27 12:00:00 -0300')
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: [{ permission: 'ads_management', status: 'granted' }] }.to_json, headers: json)
  end

  describe '#read' do
    it 'orçamento por dia no grupo, em reais, com quantos anúncios do grupo estão no ar' do
      stub_budget(adset: { daily_budget: '3000' })
      stub_ads(adset_id, %w[ACTIVE ACTIVE PAUSED])
      stub_currency

      expect(described_class.new(connection).read(ad_id)).to eq(
        level: 'adset', object_id: adset_id, object_name: 'Público 25-45', kind: 'daily', amount: 30.0, currency: 'BRL',
        start_time: '2026-10-01T09:00:00-0300', end_time: nil, started: true, ads_count: 3, active_ads_count: 2,
        min_daily: 6, max_daily: 500, can_change: true, adset_id: adset_id
      )
    end

    it 'orçamento total na campanha quando o grupo não tem orçamento próprio' do
      stub_budget(adset: { end_time: '2026-11-30T23:59:00-0300' }, campaign: { lifetime_budget: '90000' })
      stub_ads(campaign_id, %w[PAUSED])
      stub_currency

      expect(described_class.new(connection).read(ad_id)).to include(
        level: 'campaign', object_id: campaign_id, object_name: 'Vendas', kind: 'lifetime', amount: 900.0,
        end_time: '2026-11-30T23:59:00-0300', ads_count: 1, active_ads_count: 0
      )
    end

    it 'conta em outra moeda: lê, mas não deixa mudar (os limites são em reais)' do
      stub_budget(adset: { daily_budget: '3000' })
      stub_ads(adset_id, %w[ACTIVE])
      stub_currency('USD')

      expect(described_class.new(connection).read(ad_id)).to include(currency: 'USD', can_change: false)
    end

    it 'Meta fora do ar vira erro, nunca orçamento vazio (ponto 11)' do
      stub_budget(status: 500)

      expect { described_class.new(connection).read(ad_id) }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
        expect(e.code).to eq('meta_unavailable')
      }
    end

    it 'anúncio de outra conta de anúncios não existe' do
      stub_budget(adset: { daily_budget: '3000' }, account_id: '999')

      expect { described_class.new(connection).read(ad_id) }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
        expect(e.code).to eq('ad_not_found')
      }
    end

    it 'id com caractere que não é dígito não chega à Meta' do
      expect { described_class.new(connection).read('1/ads') }.to raise_error(Crm::MetaAds::Creation::Error) { |e|
        expect(e.code).to eq('ad_not_found')
      }
      expect(a_request(:get, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe '#change!' do
    before do
      stub_budget(adset: { daily_budget: '3000' })
      stub_ads(adset_id, %w[ACTIVE])
      stub_currency
    end

    it 'grava o valor novo em centavos no grupo e o fim no fuso da conta de anúncios' do
      update = stub_request(:post, meta_graph_url(adset_id))
               .with(body: { 'daily_budget' => '4550', 'end_time' => '2026-11-30T23:59:00-03:00' })
               .to_return(status: 200, body: { success: true }.to_json, headers: json)

      result = described_class.new(connection).change!(ad_id, amount: '45.5', end_time: '2026-11-30T23:59:00')

      expect(update).to have_been_made.once
      expect(result[:before]).to include(amount: 30.0, end_time: nil)
    end

    it 'só manda o que mudou' do
      update = stub_request(:post, meta_graph_url(adset_id)).with(body: { 'daily_budget' => '5000' })
                                                            .to_return(status: 200, body: { success: true }.to_json, headers: json)

      described_class.new(connection).change!(ad_id, amount: '50', end_time: nil)

      expect(update).to have_been_made.once
    end

    it 'recusa valor por dia fora de R$ 6 a R$ 500, sem chamar a Meta' do
      %w[5.99 500.01 abc].each do |amount|
        expect { described_class.new(connection).change!(ad_id, amount: amount, end_time: nil) }
          .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_amount') }
      end
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'recusa fim que já passou' do
      expect { described_class.new(connection).change!(ad_id, amount: '30', end_time: '2026-10-26T23:59:00') }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_dates') }
    end

    it 'Meta recusou: erro meta_refused' do
      stub_request(:post, meta_graph_url(adset_id)).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)

      expect { described_class.new(connection).change!(ad_id, amount: '40', end_time: nil) }
        .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_refused') }
    end
  end
end
