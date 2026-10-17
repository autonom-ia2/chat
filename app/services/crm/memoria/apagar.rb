# Apagamento (#1601, LGPD; decisão N3 do Rodrigo: sem retenção e sem "apagar de vez", só o mínimo). Apagar o contato
# apaga a memória dele:
# - as linhas com contact_id (autoria, e os fatos no PR 3) saem pela FK com ON DELETE CASCADE, mesmo num delete cru;
# - aqui, na transação do destroy (ContactMemoria, before_destroy): o bilhete das passagens das conversas dele (as
#   conversas saem depois, em segundo plano) e as tarefas de retomar dele. O bilhete apagado fica com o status
#   terminal 'apagado': nenhum escritor (o código, a IA no meio da chamada, a conciliação) grava nele de novo.
# Na mescla de contatos (ContactMergeAction), as conversas e as tarefas do absorvido já passaram para o que fica antes
# do destroy!: aqui não acha nada dele.
module Crm::Memoria::Apagar
  module_function

  def contato!(contact)
    conversas = Conversation.where(account_id: contact.account_id, contact_id: contact.id).select(:id)
    Crm::Passagem.where(account_id: contact.account_id, conversation_id: conversas)
                 .update_all(bilhete: nil, bilhete_status: Crm::Memoria::Bilhete::APAGADO, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Crm::FollowUp.where(account_id: contact.account_id, contact_id: contact.id).where("crm_follow_ups.metadata -> 'memoria' IS NOT NULL")
                 .delete_all
  end

  # Varredura diária (o caminho principal falhou): bilhete de passagem cuja conversa ficou sem contato.
  def orfaos!
    Crm::Passagem.where.not(bilhete: nil)
                 .where('NOT EXISTS (SELECT 1 FROM conversations c JOIN contacts k ON k.id = c.contact_id ' \
                        'WHERE c.id = crm_passagens.conversation_id)')
                 .update_all(bilhete: nil, bilhete_status: Crm::Memoria::Bilhete::APAGADO, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
