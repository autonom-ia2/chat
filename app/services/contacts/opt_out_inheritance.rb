# A recusa de mensagens ativas é da pessoa do número ou do e-mail, não do registro do contato (chat#713). Um contato que
# nasce depois (mensagem no inbox, importação, criação manual, API) ou que passa a ter o telefone ou o e-mail de quem
# recusou herda a recusa que ainda vale na conta:
# - 'email_unsubscribe': o e-mail do contato se descadastrou das campanhas de e-mail da conta;
# - 'prospecting': um lead recusado da conta (consent_refused_at ou no_consent) alcança o contato (ConsentVeto#contact_vetoed?).
#
# source_for também diz, quando a recusa da Prospecção sai, se outra recusa ainda sustenta a marca (ContactOptOutSync).
class Contacts::OptOutInheritance
  EMAIL_SOURCE = 'email_unsubscribe'.freeze
  PROSPECTING_SOURCE = 'prospecting'.freeze

  # Consulta barata, feita no commit do contato, para só enfileirar a herança quando há o que herdar.
  def self.possible_for?(contact)
    return false if contact.phone_number.blank? && contact.email.blank?

    Autonomia::Prospecting::Lead.where(account_id: contact.account_id).consent_refused.exists? ||
      EmailSuppression.unsubscribed?(contact.account, contact.email)
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
    return EMAIL_SOURCE if EmailSuppression.unsubscribed?(@account, contact.email)

    PROSPECTING_SOURCE if consent_veto.contact_vetoed?(contact)
  end

  private

  def consent_veto
    @consent_veto ||= Autonomia::Prospecting::ConsentVeto.new(account: @account)
  end
end
