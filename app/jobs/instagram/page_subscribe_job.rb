# Instagram pelo login único (#2406): inscreve no webhook a Página dona do token da caixa. No login do Facebook, os
# eventos do Instagram chegam pela Página inscrita no app (a mesma Página do Messenger), e não pelo subscribed_apps da
# conta do Instagram. Só soma os campos do Messenger: os outros recursos da Página ficam como estão
# (Crm::MetaAds::PageSubscription). Erro passageiro tenta de novo; recusa fica no log.
class Instagram::PageSubscribeJob < ApplicationJob
  queue_as :low

  ATTEMPTS = 3

  def perform(channel_id, attempt: 1)
    channel = Channel::Instagram.find_by(id: channel_id)
    return unless channel&.facebook_login?

    Crm::MetaAds::PageSubscription.new(page_id: channel.page_id, access_token: channel.access_token)
                                  .add!(Channel::FacebookPage::MESSENGER_FIELDS)
  rescue Crm::MetaAds::PageSubscription::Error => e
    return Rails.logger.warn("[#{self.class.name}] channel=#{channel_id} code=#{e.code.inspect}") unless e.transient? && attempt < ATTEMPTS

    self.class.set(wait: (attempt * 30).seconds).perform_later(channel_id, attempt: attempt + 1)
  end
end
