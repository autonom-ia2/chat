# Assina o campo `messaging_referrals` numa Página do Messenger (#2521): a caixa nova enfileira na criação
# (Channel::FacebookPage#subscribe); a Página que já era caixa antes, pela tarefa autonomia:meta_ads:assinar_referrals.
# Só soma o campo: os outros recursos da Página ficam como estão (Crm::MetaAds::PageSubscription).
#
# A mesma Página pode ser caixa de mais de uma conta: se o token de uma for recusado, tenta o da próxima. Erro
# passageiro (rede, 5xx, limite, trava ocupada) tenta de novo mais tarde; recusa de todas fica no log.
class Crm::MetaAds::MessagingReferralsSubscribeJob < ApplicationJob
  queue_as :low

  ATTEMPTS = 3

  def perform(page_id, attempt = 1)
    channels = Channel::FacebookPage.where(page_id: page_id.to_s).order(:id).reject(&:reauthorization_required?)
    return if channels.empty? || channels.any? { |channel| subscribed?(channel) }

    Rails.logger.warn("[#{self.class.name}] page=#{page_id} sem token aceito (#{channels.size} caixa(s))")
  rescue Crm::MetaAds::PageSubscription::Error => e
    return Rails.logger.warn("[#{self.class.name}] page=#{page_id} desistiu: #{e.message}") if attempt >= ATTEMPTS

    self.class.set(wait: (attempt * 30).seconds).perform_later(page_id, attempt + 1)
  end

  private

  # true quando o campo ficou; recusa do token desta caixa é false (tenta a próxima); erro passageiro sobe.
  def subscribed?(channel)
    Crm::MetaAds::PageSubscription.new(page_id: channel.page_id, access_token: channel.page_access_token)
                                  .add!(Channel::FacebookPage::REFERRAL_FIELDS)
    true
  rescue Crm::MetaAds::PageSubscription::Error => e
    raise if e.transient?

    Rails.logger.warn("[#{self.class.name}] channel=#{channel.id} code=#{e.code.inspect} http=#{e.http_code.inspect}: #{e.message}")
    false
  end
end
