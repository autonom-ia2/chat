# O anúncio de clique para o Messenger ou o Direct (#2521) que chegou numa Página de mais de uma conta, quando nenhuma
# conta conhece o anúncio ainda: a pergunta à Graph de qual conta de anúncios ele é (até 8 s) sai da trava por contato
# do webhook e roda aqui (Crm::MetaAds::MessagingReferral.attribute!, ask_owner). Grava o toque só se esta conta for a
# dona. O referral vem sem links assinados (MessagingReferral.slim).
class Crm::MetaAds::MessagingReferralOwnerJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, referral, source, event_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil?

    Crm::MetaAds::MessagingReferral.attribute!(conversation, referral, source: source, event_id: event_id)
  end
end
