# A recusa de mensagens ativas é da pessoa do número ou do e-mail, não do registro do contato (chat#713). Um contato que
# nasce depois (mensagem no inbox, importação, criação manual, API) ou que passa a ter o telefone ou o e-mail de quem
# recusou herda a recusa que ainda vale na conta:
# - 'email_unsubscribe': o e-mail do contato se descadastrou das campanhas de e-mail da conta;
# - 'prospecting': um lead recusado da conta (consent_refused_at ou no_consent) alcança o contato (ConsentVeto#contact_vetoed?);
# - 'campaign_reply': outro contato da conta pediu para parar, na resposta a uma campanha, neste telefone (#1449).
#
# source_for também diz, quando uma recusa sai, se outra ainda sustenta a marca (ContactOptOutSync, release_opt_out!).
# Ali entra também 'follow_up_reply' (chat#1325): a prova dela é um card do contato marcado pelo pedido de parar no
# follow-up de IA (Crm::FollowUps::CardOptOut). Ela vem primeiro, na mesma ordem da fusão (ContactMergeAction), e é
# do próprio contato: um contato novo não tem card marcado. Depois dela, 'campaign_reply' (#1449): a recusa que a IA
# reconheceu na resposta a uma campanha vale pelo número, e a prova é o contato que pediu para parar nele
# (Contacts::CampaignReplyOptOut). 'manual' não tem prova fora do contato e não volta sozinha.
class Contacts::OptOutInheritance
  FOLLOW_UP_SOURCE = 'follow_up_reply'.freeze
  CAMPAIGN_SOURCE = Contacts::CampaignReplyOptOut::SOURCE
  EMAIL_SOURCE = 'email_unsubscribe'.freeze
  PROSPECTING_SOURCE = 'prospecting'.freeze

  # Consulta barata, feita no commit do contato, para só enfileirar a herança quando há o que herdar.
  def self.possible_for?(contact)
    return false if contact.phone_number.blank? && contact.email.blank?

    Autonomia::Prospecting::Lead.where(account_id: contact.account_id).consent_refused.exists? ||
      EmailSuppression.unsubscribed?(contact.account, contact.email) ||
      Contacts::CampaignReplyOptOut.number_marked?(contact)
  end

  def initialize(account:, consent_veto: nil)
    @account = account
    @consent_veto = consent_veto
  end

  # Marca os contatos ainda sem recusa que têm uma recusa viva para herdar. Recusa que o contato já tem fica como está.
  def apply(contacts)
    contacts.each do |contact|
      next if contact.opted_out?

      source = source_for(contact)
      contact.opt_out!(source: source) if source
    end
  end

  # A origem da recusa que vale hoje para o contato, ou nil.
  def source_for(contact)
    return FOLLOW_UP_SOURCE if Crm::FollowUps::CardOptOut.contact_marked?(contact)
    return CAMPAIGN_SOURCE if Contacts::CampaignReplyOptOut.number_marked?(contact)
    return EMAIL_SOURCE if EmailSuppression.unsubscribed?(@account, contact.email)

    PROSPECTING_SOURCE if consent_veto.contact_vetoed?(contact)
  end

  private

  def consent_veto
    @consent_veto ||= Autonomia::Prospecting::ConsentVeto.new(account: @account)
  end
end
