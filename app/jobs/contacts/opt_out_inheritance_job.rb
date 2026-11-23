# Herança da recusa de mensagens ativas por contato novo ou que mudou de telefone ou e-mail (chat#713). Fora do request:
# a leitura das recusas da Prospecção percorre os leads recusados da conta.
class Contacts::OptOutInheritanceJob < ApplicationJob
  queue_as :low

  # Enqueues only the contacts that were saved (an import batch may skip invalid rows).
  def self.perform_for(account, contacts)
    contact_ids = contacts.filter_map(&:id)
    perform_later(account, contact_ids) if contact_ids.any?
  end

  def perform(account, contact_ids)
    Contacts::OptOutInheritance.new(account: account).apply(account.contacts.not_opted_out.where(id: contact_ids))
  end
end
