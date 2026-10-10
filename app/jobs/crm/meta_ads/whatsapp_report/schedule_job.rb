# Agendador do resumo e do alerta no WhatsApp (#1100, F4b), chamado pelo sidekiq-cron (config/schedule.yml):
# - `summary` às 8h de Brasília (11:00 UTC): o resumo de ontem;
# - `alert` às 16h30 de Brasília (19:30 UTC): o anúncio que gastou hoje sem trazer conversa.
#
# Passa por cada conexão ativa com conta de anúncios, Anúncios da Meta ligado (`meta_ads_hub`) e o tipo ligado na
# configuração, e enfileira um envio por conta. A trava de um por dia fica no DeliverJob.
class Crm::MetaAds::WhatsappReport::ScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  FEATURE = 'meta_ads_hub'.freeze

  def perform(kind)
    raise ArgumentError, "unknown kind #{kind}" unless Crm::MetaAdsConnection::WHATSAPP_REPORT_FLAGS.key?(kind)

    connections(kind).find_each do |connection|
      next unless connection.account.feature_enabled?(FEATURE)

      Crm::MetaAds::WhatsappReport::DeliverJob.perform_later(connection.id, kind)
    end
  end

  private

  def connections(kind)
    Crm::MetaAdsConnection.active.where.not(ad_account_id: nil).whatsapp_report_on(kind).includes(:account)
  end
end
