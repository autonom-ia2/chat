# Assina o campo `messaging_referrals` numa Página que já era caixa do Messenger antes do #2521 (a caixa nova já
# assina na criação, Channel::FacebookPage::MESSENGER_FIELDS). Só soma o campo: os outros recursos da Página ficam
# como estão (Crm::MetaAds::PageSubscription). Roda pela tarefa autonomia:meta_ads:assinar_referrals, nunca sozinho.
#
# Erro passageiro (rede, 5xx, limite, trava ocupada) tenta de novo; recusa (token inválido, sem permissão) fica no log.
class Crm::MetaAds::MessagingReferralsSubscribeJob < ApplicationJob
  queue_as :low

  FIELDS = %w[messaging_referrals].freeze
  ATTEMPTS = 3

  def perform(channel_id, attempt = 1)
    page = Channel::FacebookPage.find_by(id: channel_id)
    return if page.nil? || page.reauthorization_required?

    Crm::MetaAds::PageSubscription.new(page_id: page.page_id, access_token: page.page_access_token).add!(FIELDS)
  rescue Crm::MetaAds::PageSubscription::Error => e
    return self.class.set(wait: (attempt * 30).seconds).perform_later(channel_id, attempt + 1) if e.transient? && attempt < ATTEMPTS

    Rails.logger.warn("[#{self.class.name}] channel=#{channel_id} code=#{e.code.inspect} http=#{e.http_code.inspect}: #{e.message}")
  end
end
