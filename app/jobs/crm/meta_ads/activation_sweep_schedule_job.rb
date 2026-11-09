# "Teve anúncio" em Seus posts (#2804): de hora em hora (config/schedule.yml), um Crm::MetaAds::ActivationSweepJob por
# conexão com Anúncios da Meta e Seus posts ligados (FEATURES), conta de anúncios escolhida e algum anúncio criado aqui a partir
# de um post nos últimos Crm::MetaAds::Creation::ActivationSweep::WINDOW. Conta sem anúncio assim nem ganha job.
#
# A trava por conexão garante uma leitura por rodada: o job da rodada anterior ainda na fila não ganha outro. Ela sai no
# fim do job; o prazo só vale se o job nunca rodar.
class Crm::MetaAds::ActivationSweepScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  FEATURES = %w[meta_ads_hub seus_posts].freeze

  def self.enabled?(account)
    FEATURES.all? { |flag| account.feature_enabled?(flag) }
  end
  LOCK_TTL = 3.hours

  def self.lock_key(connection_id)
    ['crm_meta_ads', 'activation_sweep', connection_id]
  end

  def perform
    connections.find_each do |connection|
      next unless self.class.enabled?(connection.account)
      next unless Rails.cache.write(self.class.lock_key(connection.id), true, expires_in: LOCK_TTL, unless_exist: true)

      Crm::MetaAds::ActivationSweepJob.perform_later(connection.id)
    end
  end

  private

  def connections
    boosted = Crm::MetaAdsCreatedObject.where(status: 'created').where.not(ad_id: nil).where.not(source_post_id: nil)
                                       .where(created_at: Crm::MetaAds::Creation::ActivationSweep::WINDOW.ago..)
    Crm::MetaAdsConnection.active.where.not(ad_account_id: nil).where(account_id: boosted.select(:account_id)).includes(:account)
  end
end
