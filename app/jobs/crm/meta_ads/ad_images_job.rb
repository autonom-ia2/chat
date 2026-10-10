# Renova a imagem dos anúncios de uma conexão (#1088). Ver Crm::MetaAds::AdImages.
#
# Uma vez por dia por conexão (DAILY_KEY): na rodada das 4h e na primeira abertura da tela no dia. Se a leitura
# falha (Meta recusou, erro no meio), a chave passa a valer só RETRY_AFTER: a próxima abertura da tela depois disso
# tenta de novo, em vez de esperar o dia seguinte. Conta pausada por limite de uso não enfileira. Avisa a tela
# aberta quando termina.
class Crm::MetaAds::AdImagesJob < ApplicationJob
  queue_as :low

  DAILY_KEY = 'crm:meta_ads:ad_images'.freeze
  EVERY = 1.day
  RETRY_AFTER = 30.minutes

  def self.start(connection)
    return false if Crm::MetaAds::Insights::Usage.paused?(connection.ad_account_id)
    return false unless Redis::Alfred.set(key(connection.id), 1, nx: true, ex: EVERY.to_i)

    perform_later(connection.id)
    true
  end

  def self.key(connection_id)
    "#{DAILY_KEY}:#{connection_id}"
  end

  def perform(connection_id)
    connection = Crm::MetaAdsConnection.find_by(id: connection_id)
    return if connection.blank?

    refreshed = Crm::MetaAds::AdImages.new(connection).refresh!
    return retry_soon(connection_id) if refreshed.nil?

    Crm::MetaAds::Insights::Broadcaster.broadcast_throttled(connection) if refreshed.positive?
  rescue StandardError
    retry_soon(connection_id)
    raise
  end

  private

  def retry_soon(connection_id)
    Redis::Alfred.set(self.class.key(connection_id), 1, ex: RETRY_AFTER.to_i)
  end
end
