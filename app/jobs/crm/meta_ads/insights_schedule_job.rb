# Agendador da coleta de insights (#1073), chamado pelo sidekiq-cron (config/schedule.yml):
# - `today` a cada 30 minutos: o gasto de hoje de cada conexão;
# - `recent` todo dia às 4h de Brasília: os 3 dias anteriores, com posicionamento. Conexão que ainda não
#   terminou a primeira carga de 90 dias recebe a carga no lugar; sem as ligações conversa → anúncio dos 90 dias
#   (F2b), recebe também essa carga, que só lê o banco.
#
# Só lê contas com Anúncios da Meta ligado (`meta_ads_hub`) e conta de anúncios escolhida. Cada conexão vira
# um job próprio, com a trava do escopo: uma leitura por conta de anúncios por rodada (CA-2.1).
class Crm::MetaAds::InsightsScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  FEATURE = 'meta_ads_hub'.freeze

  def perform(scope)
    raise ArgumentError, "unknown scope #{scope}" unless Crm::MetaAds::Insights::Sync::SCOPES.include?(scope)

    connections.find_each do |connection|
      next unless connection.account.feature_enabled?(FEATURE)

      start_daily_loads(connection) if scope == 'recent'

      if scope == 'recent' && connection.insights_backfilled_at.nil?
        Crm::MetaAds::InsightsBackfillJob.start(connection)
      else
        enqueue_sync(connection, scope)
      end
    end
  end

  private

  # Não chamar de `enqueue`: o nome sobrescreve ActiveJob::Base#enqueue, que o perform_later do sidekiq-cron
  # usa, e todo agendamento falha (#1073).
  # Uma vez por dia: as ligações dos 90 dias que faltam (só banco) e a imagem dos anúncios.
  def start_daily_loads(connection)
    Crm::MetaAds::LinksBackfillJob.start(connection) if connection.links_backfilled_at.nil?
    Crm::MetaAds::AdImagesJob.start(connection)
  end

  def enqueue_sync(connection, scope)
    return unless Crm::MetaAds::Insights::Refresh.claim(connection.id, scope)

    Crm::MetaAds::InsightsSyncJob.perform_later(connection.id, scope)
  end

  def connections
    Crm::MetaAdsConnection.active.where.not(ad_account_id: nil).includes(:account)
  end
end
