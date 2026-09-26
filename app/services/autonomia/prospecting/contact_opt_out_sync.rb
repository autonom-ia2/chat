# Recusa da Prospecção gravada no contato (chat#713). O lead em no_consent é a pessoa pedindo para não receber mensagem
# ativa; a marca vai para o contato, onde campanhas e follow-ups a leem.
#
# - Lead que vira no_consent: marca, com a origem 'prospecting', o contato dele e os contatos da conta que a recusa
#   alcança pelo telefone ou pelo e-mail (ConsentVeto#contacts_vetoed_by). Recusa que o contato já tinha fica como está.
# - Lead que sai de no_consent: tira só a marca de origem 'prospecting' dos mesmos contatos, e só onde nenhum outro lead
#   recusado da conta ainda alcança o contato (vários leads podem dividir o número: central, franquia). Recusa manual ou
#   de descadastro de e-mail nunca sai por aqui; descadastro feito enquanto a marca da Prospecção valia vira a origem.
#
# update_lead! roda na mesma transação que grava o status do lead: a recusa e a marca entram ou saem juntas.
class Autonomia::Prospecting::ContactOptOutSync
  SOURCE = 'prospecting'.freeze
  REFUSED_STATUS = 'no_consent'.freeze

  def initialize(account:)
    @account = account
  end

  # O PATCH do lead: grava os atributos e, se o status mudou, a recusa nos contatos, tudo numa transação.
  def update_lead!(lead, attributes)
    ActiveRecord::Base.transaction do
      lead.update!(attributes)
      apply(lead, previous_status: lead.status_before_last_save) if lead.saved_change_to_status?
    end
  end

  # previous_status: o status do lead antes da mudança que acabou de ser gravada.
  def apply(lead, previous_status:)
    if lead.no_consent?
      reached_contacts(lead).each { |contact| contact.opt_out!(source: SOURCE) }
    elsif previous_status.to_s == REFUSED_STATUS
      release(lead)
    end
  end

  private

  # A marca de origem 'prospecting' só sai quando nenhuma outra recusa viva a sustenta. Se a pessoa se descadastrou do
  # e-mail enquanto a marca da Prospecção valia (a primeira recusa vale, então o descadastro não trocou a origem), a
  # recusa continua, agora com a origem do descadastro.
  def release(lead)
    inheritance = Contacts::OptOutInheritance.new(account: @account, consent_veto: veto)
    reached_contacts(lead).each do |contact|
      next if contact.opt_out_source != SOURCE

      source = inheritance.source_for(contact)
      next if source == SOURCE

      source ? contact.transfer_opt_out!(from: SOURCE, to: source) : contact.opt_in!(source: SOURCE)
    end
  end

  # O contato que a Prospecção usaria para o lead (o ligado ou o achado pelo telefone, identificador ou e-mail) e os que o
  # mesmo telefone ou e-mail alcança na conta.
  def reached_contacts(lead)
    own = Autonomia::Prospecting::ContactConverter.new(lead: lead, user: nil).existing_contact
    [own, *veto.contacts_vetoed_by(lead)].compact.uniq(&:id)
  end

  # Lido depois de o novo status estar gravado: o lead que acabou de sair de no_consent já não conta como recusa.
  def veto
    @veto ||= Autonomia::Prospecting::ConsentVeto.new(account: @account)
  end
end
