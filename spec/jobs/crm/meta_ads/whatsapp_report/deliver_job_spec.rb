require 'rails_helper'

# Envio agendado do resumo e do alerta (#1100, F4b): no máximo um de cada por dia, falha registrada, e nunca
# reenviar quando não se sabe se saiu. O Sender é stub: nenhum envio real.
RSpec.describe Crm::MetaAds::WhatsappReport::DeliverJob do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:sender) { instance_double(Crm::MetaAds::WhatsappReport::Sender) }
  let(:now) { Time.zone.parse('2026-10-07T08:00:00-03:00') }
  let(:error) { Crm::MetaAds::WhatsappReport::Settings::Error }

  def spend_yesterday(value = 40)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: '1', date: Date.new(2026, 10, 6),
                                    currency: 'BRL', spend: value, attribution_window: '7d_click', fetched_at: now)
  end

  def settings
    connection.reload.whatsapp_report_settings
  end

  before do
    account.enable_features!('meta_ads_hub')
    connection.update!(whatsapp_report: { 'enabled' => true, 'alert_enabled' => true, 'inbox_id' => 1 }, whatsapp_report_phone: '+5511987654321')
    allow(Crm::MetaAds::WhatsappReport::Sender).to receive(:new).and_return(sender)
  end

  after do
    travel_to(now) { %w[summary alert].each { |kind| Redis::Alfred.delete(described_class.lock_key(connection, kind)) } }
  end

  it 'manda o resumo uma vez por dia e grava quando saiu' do
    travel_to(now) do
      spend_yesterday
      allow(sender).to receive(:send_summary).and_return(true)

      2.times { described_class.perform_now(connection.id, 'summary') }

      expect(sender).to have_received(:send_summary).once.with(hash_including(date: Date.new(2026, 10, 6), spend: 40.0))
      expect(settings).to include('last_summary_at' => now.utc.iso8601, 'last_error' => nil)
    end
  end

  it 'falha clara solta a trava e grava o motivo; sem saber se saiu, a trava fica' do
    travel_to(now) do
      spend_yesterday
      allow(sender).to receive(:send_summary).and_raise(error.new('template_not_approved'))

      described_class.perform_now(connection.id, 'summary')

      expect(settings).to include('last_error' => 'template_not_approved')
      expect(settings).not_to have_key('last_summary_at')
      expect(Redis::Alfred.exists?(described_class.lock_key(connection, 'summary'))).to be(false)

      allow(sender).to receive(:send_summary).and_raise(error.new('send_uncertain'))
      2.times { described_class.perform_now(connection.id, 'summary') }

      expect(sender).to have_received(:send_summary).twice
      expect(settings).to include('last_error' => 'send_uncertain')
    end
  end

  it 'ontem sem gasto nem conversa não envia e registra nothing_to_report' do
    travel_to(now) do
      allow(sender).to receive(:send_summary)

      described_class.perform_now(connection.id, 'summary')

      expect(sender).not_to have_received(:send_summary)
      expect(settings['last_error']).to eq('nothing_to_report')
    end
  end

  it 'alerta só sai com um anúncio no critério' do
    afternoon = Time.zone.parse('2026-10-07T16:30:00-03:00')
    travel_to(afternoon) do
      allow(sender).to receive(:send_alert).and_return(true)
      described_class.perform_now(connection.id, 'alert')
      expect(sender).not_to have_received(:send_alert)

      Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: '9', date: Date.new(2026, 10, 7),
                                      currency: 'BRL', spend: 45, attribution_window: '7d_click', fetched_at: afternoon)
      described_class.perform_now(connection.id, 'alert')

      expect(sender).to have_received(:send_alert).once.with(hash_including(ad_id: '9', spend: 45.0))
      expect(settings['last_alert_at']).to eq(afternoon.utc.iso8601)
    end
  end

  it 'não envia com o tipo desligado ou sem Anúncios da Meta ligado' do
    travel_to(now) do
      spend_yesterday
      allow(sender).to receive(:send_summary)
      connection.update!(whatsapp_report: { 'enabled' => false })
      described_class.perform_now(connection.id, 'summary')

      connection.update!(whatsapp_report: { 'enabled' => true })
      account.disable_features!('meta_ads_hub')
      described_class.perform_now(connection.id, 'summary')

      expect(sender).not_to have_received(:send_summary)
    end
  end
end
