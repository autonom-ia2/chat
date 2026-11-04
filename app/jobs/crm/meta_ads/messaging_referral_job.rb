# O evento só de referral do Messenger e do Instagram (#2521): a pessoa clicou num anúncio de mensagem e já tinha
# conversa com a Página ou o perfil. Grava o anúncio na conversa mais recente dela na caixa
# (Crm::MetaAds::MessagingReferral.attribute_to_latest!).
#
# network: 'messenger' (recipient = id da Página) ou 'instagram' (recipient = id da conta do Instagram, pelo login do
# Instagram ou pela Página do Facebook).
class Crm::MetaAds::MessagingReferralJob < ApplicationJob
  queue_as :default
  # A foto do anúncio vem num link assinado da Meta: não vai para o log.
  self.log_arguments = false

  # { 'messenger' => 'meta_ctm', 'instagram' => 'meta_ctd' }
  SOURCES = Crm::MetaAds::MessagingReferral::ORIGINS.invert.freeze

  # messaging: o evento do webhook (chaves em texto). Vai para a fila só o anúncio sem links assinados
  # (Crm::MetaAds::MessagingReferral.slim); referral que não é anúncio não enfileira.
  def self.enqueue_for(network, messaging)
    referral = Crm::MetaAds::MessagingReferral.slim(messaging['referral'])
    return if referral.nil?

    perform_later(network, messaging.dig('recipient', 'id').to_s, messaging.dig('sender', 'id').to_s, referral, messaging['timestamp'].to_s)
  end

  def perform(network, recipient_id, sender_id, referral, timestamp)
    # Sem a hora, o id do evento seria o mesmo para todo clique do contato e o próximo cairia como reentrega.
    return if timestamp.blank?

    inboxes_for(network, recipient_id.to_s).each do |inbox|
      Crm::MetaAds::MessagingReferral.attribute_to_latest!(inbox, sender_id, referral, source: SOURCES.fetch(network),
                                                                                       event_id: "#{sender_id}:#{timestamp}")
    end
  end

  private

  # Como na mensagem: a Página pode ser caixa de mais de uma conta (Integrations::Facebook::MessageCreator); no
  # Instagram vale o canal que o InstagramEventsJob acha (login do Instagram primeiro, depois a Página).
  def inboxes_for(network, recipient_id)
    return Channel::FacebookPage.where(page_id: recipient_id).filter_map(&:inbox) if network == 'messenger'

    channel = Channel::Instagram.find_by(instagram_id: recipient_id) || Channel::FacebookPage.find_by(instagram_id: recipient_id)
    [channel&.inbox].compact
  end
end
