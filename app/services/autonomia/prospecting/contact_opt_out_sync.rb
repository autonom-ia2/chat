# Recusa da Prospecção gravada no contato (chat#713). O lead recusado (consent_refused_at, ou o status no_consent, que
# grava a data) é a pessoa pedindo para não receber mensagem ativa; a marca vai para o contato, onde campanhas e
# follow-ups a leem.
#
# A recusa do lead não depende do status (decisão de 26/09): descartar, requalificar ou desfazer o descarte não a tira.
# - Lead que passa a recusar (botão "Não quer ser contatado" ou status no_consent): marca, com a origem 'prospecting', o
#   contato dele e os contatos da conta que a recusa alcança pelo telefone ou pelo e-mail (ConsentVeto#contacts_vetoed_by).
#   Recusa que o contato já tinha fica como está.
# - Recusa desfeita de propósito (withdraw!, consent_refused_at volta a nulo): tira só a marca de origem 'prospecting'
#   dos mesmos contatos, e só onde nenhum outro lead recusado da conta ainda alcança o contato (vários leads podem
#   dividir o número: central, franquia). Recusa manual ou de descadastro de e-mail nunca sai por aqui; descadastro
#   feito enquanto a marca da Prospecção valia vira a origem. Só saem os contatos que o próprio lead alcança hoje: a
#   marca posta com um número que o lead deixou de ter, ou que chegou a um contato por mescla ou pelo converter, fica.
#   Marca que sobra é o erro conservador; quem recusou não volta a receber por engano.
# - Lead recusado que ganha telefone, WhatsApp ou e-mail novo: o callback do Lead chama mark_contacts! de novo.
#
# Tudo roda na mesma transação que grava o lead: a recusa e a marca entram ou saem juntas.
class Autonomia::Prospecting::ContactOptOutSync
  SOURCE = 'prospecting'.freeze

  def initialize(account:)
    @account = account
  end

  # O PATCH do lead: grava os atributos e, se a recusa mudou, a marca nos contatos.
  def update_lead!(lead, attributes)
    ActiveRecord::Base.transaction do
      was_refused = lead.consent_refused?
      lead.update!(attributes)
      apply(lead, was_refused: was_refused)
    end
    lead
  end

  # O botão "Não quer ser contatado". Lead que já recusou fica como está.
  def refuse!(lead, user:)
    return lead if lead.consent_refused_at.present?

    update_lead!(lead, consent_refused_at: Time.current, consent_refused_by_id: user&.id)
  end

  # O "Desfazer: pode ser contatado". O lead em no_consent volta a novo, senão o status manteria a recusa.
  def withdraw!(lead)
    attributes = { consent_refused_at: nil, consent_refused_by_id: nil }
    attributes[:status] = :new_lead if lead.no_consent?
    update_lead!(lead, attributes)
  end

  # Marca a recusa do lead nos contatos que ela alcança. Também é o que passa para o contato a recusa gravada antes da
  # coluna no contato existir (Contacts::OptOutBackfill). Recusa que o contato já tem fica como está.
  def mark_contacts!(lead)
    reached_contacts(lead).each { |contact| contact.opt_out!(source: SOURCE) }
  end

  private

  def apply(lead, was_refused:)
    if lead.consent_refused?
      mark_contacts!(lead) unless was_refused
    elsif was_refused
      release(lead)
    end
  end

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

  # Lido depois de a recusa nova estar gravada: o lead que acabou de desfazer a recusa já não conta.
  def veto
    @veto ||= Autonomia::Prospecting::ConsentVeto.new(account: @account)
  end
end
