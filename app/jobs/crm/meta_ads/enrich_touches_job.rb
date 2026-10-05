# Resolve os nomes da Meta nos toques de uma conversa (#1034). Ver Crm::MetaAds::TouchEnricher.
#
# Enfileirado por Ctwa::CampaignBuilder.attribute! depois de cada toque gravado que tenha algum ID,
# no máximo uma vez por conversa a cada THROTTLE. Um toque que chega dentro da janela não se perde:
# agenda uma única execução no fim dela, que lê todos os toques do momento.
class Crm::MetaAds::EnrichTouchesJob < ApplicationJob
  queue_as :low

  THROTTLE = 5.minutes
  KEY_PREFIX = 'crm:meta_ads:enrich'.freeze

  def self.enqueue_for(conversation, touch)
    return unless Crm::MetaAds::TouchEnricher.meta_ids?(touch)
    return unless Crm::MetaAdsConnection.active.exists?(account_id: conversation.account_id)

    if claim("#{KEY_PREFIX}:#{conversation.id}")
      perform_later(conversation.id)
    elsif claim("#{KEY_PREFIX}:#{conversation.id}:trailing")
      set(wait: THROTTLE).perform_later(conversation.id)
    end
  end

  def self.claim(key)
    Redis::Alfred.set(key, 1, nx: true, ex: THROTTLE.to_i) ? true : false
  end

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless Crm::MetaAdsConnection.active.exists?(account_id: conversation.account_id)

    Crm::MetaAds::TouchEnricher.new(conversation).perform
  end
end
