# Mescla de contatos (#1601, C1 da 2ª revisão). O ContactMergeAction apaga o contato absorvido (destroy!) antes de
# avisar a mescla, e a memória dele tem FK com ON DELETE CASCADE: sem isto, a autoria das mensagens (e o que mais a
# memória guardar do absorvido) sumiria com ele. Roda dentro de merge_crm_records, na transação da mescla e ANTES do
# destroy!, como os outros registros do CRM.
module Crm::Memoria::Mescla
  module_function

  def mesclar!(account:, absorvido:, fica:)
    Crm::MensagemOrigem.where(account_id: account.id, contact_id: absorvido.id)
                       .update_all(contact_id: fica.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
