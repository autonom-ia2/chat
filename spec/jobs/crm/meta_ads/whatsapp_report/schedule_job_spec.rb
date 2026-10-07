require 'rails_helper'

# Agendador do resumo e do alerta (#1100, F4b): um envio por conta que ligou o tipo, com Anúncios da Meta ligado e
# conta de anúncios escolhida. O caminho do sidekiq-cron (perform_later) é coberto em spec/configs/schedule_spec.rb.
RSpec.describe Crm::MetaAds::WhatsappReport::ScheduleJob do
  def connection_for(features: true, report: {}, ad_account_id: '2196424464528988')
    account = create(:account)
    account.enable_features!('meta_ads_hub') if features
    connection = create_meta_ads_insights_connection(account, ad_account_id: ad_account_id)
    connection.update!(whatsapp_report: report)
    connection
  end

  it 'enfileira o envio só das contas que ligaram o tipo' do
    summary = connection_for(report: { 'enabled' => true })
    alert = connection_for(report: { 'alert_enabled' => true }, ad_account_id: '111')
    connection_for(report: { 'enabled' => true }, features: false, ad_account_id: '222')
    connection_for(ad_account_id: '333')

    expect { described_class.perform_now('summary') }
      .to have_enqueued_job(Crm::MetaAds::WhatsappReport::DeliverJob).with(summary.id, 'summary').exactly(:once)
    expect { described_class.perform_now('alert') }
      .to have_enqueued_job(Crm::MetaAds::WhatsappReport::DeliverJob).with(alert.id, 'alert').exactly(:once)
  end

  it 'recusa tipo desconhecido' do
    expect { described_class.perform_now('weekly') }.to raise_error(ArgumentError)
  end

  it 'vai para a fila do agendador e enfileira como o sidekiq-cron' do
    expect { described_class.set(queue: 'scheduled_jobs').perform_later('summary') }
      .to have_enqueued_job(described_class).with('summary').on_queue('scheduled_jobs')
  end
end
