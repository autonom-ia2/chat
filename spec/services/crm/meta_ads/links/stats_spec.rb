require 'rails_helper'

# Números das ligações para a tela (#1073, F2b): conversas de anúncio de hoje e o "quanto confiar".
RSpec.describe Crm::MetaAds::Links::Stats do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  # 06/10/2026 01:30 UTC = 05/10/2026 22:30 em São Paulo.
  let(:now) { Time.utc(2026, 10, 6, 1, 30) }

  def link(conversation, certainty, touched_at, key: SecureRandom.hex(4))
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: key, origin: 'site', certainty: certainty,
                            touched_at: touched_at)
  end

  it 'conta as conversas de hoje no fuso da conta de anúncios, uma vez cada' do
    first, second, yesterday = create_list(:conversation, 3, account: account)
    travel_to(now) do
      link(first, 'ad', Time.utc(2026, 10, 5, 15))
      link(first, 'campaign', Time.utc(2026, 10, 6, 1))
      link(second, 'unknown', Time.utc(2026, 10, 5, 4))
      link(yesterday, 'ad', Time.utc(2026, 10, 5, 2))

      expect(described_class.new(connection).payload[:ad_conversations_today]).to eq(2)
    end
  end

  it 'quanto confiar: cada conversa conta pelo melhor que sabemos dela, nos últimos 30 dias' do
    best_ad, by_name, campaign, unknown, old = create_list(:conversation, 5, account: account)
    travel_to(now) do
      link(best_ad, 'unknown', 2.days.ago)
      link(best_ad, 'ad', 1.day.ago)
      link(by_name, 'ad_name', 1.day.ago)
      link(campaign, 'campaign', 3.days.ago)
      link(unknown, 'unknown', 5.days.ago)
      link(old, 'ad', 40.days.ago)

      expect(described_class.new(connection).payload[:confidence])
        .to eq(window_days: 30, conversations: 4, ad: 1, ad_name: 1, campaign: 1, unknown: 1)
    end
  end

  it 'com since, conta só desde ali e diz quantos dias são no fuso da conta, hoje incluído (F5, D5.8)' do
    recent, older = create_list(:conversation, 2, account: account)
    travel_to(now) do
      # O painel de 7 dias começa em 29/09 00:00 de São Paulo; agora ainda é 05/10 lá.
      since = ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 9, 29)
      link(recent, 'ad', since + 1.hour)
      link(older, 'ad', since - 1.minute)

      expect(described_class.new(connection, since: since).payload[:confidence])
        .to eq(window_days: 7, conversations: 1, ad: 1, ad_name: 0, campaign: 0, unknown: 0)
    end
  end

  it 'sem ligações devolve zeros' do
    expect(described_class.new(connection).payload)
      .to eq(ad_conversations_today: 0, confidence: { window_days: 30, conversations: 0, ad: 0, ad_name: 0, campaign: 0, unknown: 0 })
  end
end
