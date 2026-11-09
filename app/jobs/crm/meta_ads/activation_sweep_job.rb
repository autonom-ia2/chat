# Uma conexão da rodada de "Teve anúncio" (#2804, Crm::MetaAds::ActivationSweepScheduleJob). Conexão que caiu ou trocou
# de conta de anúncios até o job rodar é lida como está agora. A trava da rodada sai no fim.
class Crm::MetaAds::ActivationSweepJob < ApplicationJob
  queue_as :low

  def perform(connection_id)
    connection = Crm::MetaAdsConnection.active.where.not(ad_account_id: nil).find_by(id: connection_id)
    return if connection.nil? || !Crm::MetaAds::ActivationSweepScheduleJob.enabled?(connection.account)

    Crm::MetaAds::Creation::ActivationSweep.new(connection).perform
  ensure
    Rails.cache.delete(Crm::MetaAds::ActivationSweepScheduleJob.lock_key(connection_id))
  end
end
