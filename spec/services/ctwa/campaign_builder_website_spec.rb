require 'rails_helper'

# Regras de origem que entraram com a ponte da landing page (#1011).
RSpec.describe Ctwa::CampaignBuilder do
  describe '.build — Meta pago por UTM' do
    it 'classifica como meta_paid quando utm_source é da Meta e utm_medium é pago, sem fbclid (iPhone)' do
      %w[meta facebook fb instagram ig].product(%w[paid cpc ppc paid_social]).each do |source, medium|
        campaign = described_class.build(source_id: 'site:ABC234:none', source_type: 'bridge', utm_source: source, utm_medium: medium)

        expect(campaign['source']).to eq('meta_paid'), "#{source}/#{medium}"
      end
    end

    it 'compara sem diferenciar maiúsculas e espaços nas pontas' do
      campaign = described_class.build(source_id: 'x', source_type: 'bridge', utm_source: ' Facebook ', utm_medium: 'CPC')

      expect(campaign['source']).to eq('meta_paid')
    end

    it 'não classifica como meta_paid sem as duas condições' do
      base = { source_id: 'x', source_type: 'bridge' }
      [
        { utm_source: 'meta', utm_medium: 'organic' },
        { utm_source: 'google', utm_medium: 'cpc' },
        { utm_source: 'meta' },
        { utm_medium: 'paid' },
        { utm_source: 'metaverse', utm_medium: 'paid' }
      ].each do |utms|
        campaign = described_class.build(base.merge(utms))

        expect(campaign['source']).to eq('tracked_link'), utms.inspect
      end
    end

    it 'mantém a precedência: ctwa_clid, gclid e ttclid vencem as UTMs da Meta' do
      utms = { source_id: 'x', source_type: 'bridge', utm_source: 'meta', utm_medium: 'paid' }

      expect(described_class.build(utms.merge(ctwa_clid: 'c1'))['source']).to eq('meta_ctwa')
      expect(described_class.build(utms.merge(gclid: 'g1'))['source']).to eq('google_ads')
      expect(described_class.build(utms.merge(ttclid: 't1'))['source']).to eq('tiktok_ads')
    end

    it 'CTWA continua igual: referral do WhatsApp sem UTMs segue meta_ctwa (CA-3.6)' do
      campaign = described_class.build('source_id' => '120200', 'source_type' => 'ad', 'ctwa_clid' => 'ARAkLk')

      expect(campaign['source']).to eq('meta_ctwa')
      expect(campaign).not_to have_key('utm_id')
    end
  end

  describe 'utm_id' do
    it 'entra no hash da campanha e no toque' do
      conversation = create(:conversation)

      described_class.attribute!(conversation, source_id: 'site:ABC234:120211', source_type: 'bridge', headline: 'LP',
                                               utm_campaign: 'Viagem EUA', utm_id: '120211')

      attrs = conversation.reload.additional_attributes
      expect(attrs['campaign']).to include('utm_id' => '120211', 'utm_campaign' => 'Viagem EUA')
      expect(attrs['campaign_touches'].sole).to include('utm_id' => '120211')
      expect(described_class::TOUCH_KEYS).to include('utm_id')
    end
  end

  describe 'source_url só http(s)' do
    # Vem de webhook externo e vira link clicável na tela: outro esquema (javascript:, data:) não entra.
    let(:script_url) { %w[javascript //instagram.com/p/x%0aalert(1)].join(':') }

    it 'não cria toque quando a única informação é um link com outro esquema' do
      expect(described_class.build(source_url: script_url)).to be_nil
      expect(described_class.build(source_url: 'data:text/html,oi')).to be_nil
    end

    it 'grava o toque sem o link quando há identificador, e mantém http(s)' do
      expect(described_class.build(source_id: '120252711448880416', source_type: 'ad', source_url: script_url))
        .to include('source_id' => '120252711448880416').and(satisfy { |touch| !touch.key?('source_url') })
      expect(described_class.build(source_id: '1', source_url: 'HTTPS://www.instagram.com/p/DafzleSsM3W/')['source_url'])
        .to eq('HTTPS://www.instagram.com/p/DafzleSsM3W/')
    end
  end
end
