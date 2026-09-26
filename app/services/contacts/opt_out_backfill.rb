# Recusas gravadas antes da recusa no contato existir (chat#713) passam para o contato, uma vez, no deploy
# (Migration::BackfillContactOptOutJob). Campanhas e follow-ups automáticos leem só Contact.opted_out; sem isto, quem já
# tinha recusado continuaria recebendo, e a herança (OptOutInheritance) só roda quando o contato nasce ou muda de telefone
# ou e-mail.
# - Descadastro de e-mail (EmailSuppression ou EmailSuppressionState ativo, motivo 'unsubscribe'): os contatos da conta
#   com o mesmo e-mail, origem 'email_unsubscribe'.
# - Lead recusado (consent_refused_at ou no_consent, qualquer status hoje): os contatos que a recusa alcança
#   (ContactOptOutSync#mark_contacts!), origem 'prospecting'.
# O e-mail vem primeiro, como em OptOutInheritance#source_for. opt_out! não muda recusa existente: rodar de novo é seguro.
class Contacts::OptOutBackfill
  UNSUBSCRIBE = 'unsubscribe'.freeze

  def self.accounts_with_legacy_refusals
    account_ids = Autonomia::Prospecting::Lead.consent_refused.distinct.pluck(:account_id) |
                  EmailSuppression.where(reason: UNSUBSCRIBE).distinct.pluck(:account_id) |
                  EmailSuppressionState.blocking.where(reason: UNSUBSCRIBE).distinct.pluck(:account_id)
    Account.where(id: account_ids)
  end

  def initialize(account:)
    @account = account
  end

  # Devolve quantos contatos da conta estavam recusados antes e depois.
  def perform
    before = @account.contacts.opted_out.count
    mark_unsubscribed_emails
    mark_refused_leads
    { before: before, after: @account.contacts.opted_out.count }
  end

  private

  def mark_unsubscribed_emails
    emails = unsubscribed_emails
    return if emails.empty?

    @account.contacts.not_opted_out.where('LOWER(contacts.email) IN (?)', emails).find_each do |contact|
      contact.opt_out!(source: Contacts::OptOutInheritance::EMAIL_SOURCE)
    end
  end

  def unsubscribed_emails
    legacy = EmailSuppression.where(account_id: @account.id, reason: UNSUBSCRIBE).pluck(:email)
    states = EmailSuppressionState.blocking.where(account_id: @account.id, reason: UNSUBSCRIBE).pluck(:email)
    (legacy + states).map { |email| email.to_s.strip.downcase }.compact_blank.uniq
  end

  def mark_refused_leads
    sync = Autonomia::Prospecting::ContactOptOutSync.new(account: @account)
    Autonomia::Prospecting::Lead.where(account: @account).consent_refused.find_each { |lead| sync.mark_contacts!(lead) }
  end
end
