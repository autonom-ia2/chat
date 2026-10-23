# LGPD (#2096): todo contato excluído deixa os cards do CRM sem dado pessoal (Crm::Cards::Anonimizador), em vez de só
# soltá-los com título, descrição, campos, memória e textos da IA dentro (o antigo `dependent: :nullify`). Vale para
# todo caminho que destrói o contato com callbacks: o DELETE contacts/:id, a exclusão em lote, a exclusão da conta e o
# modo 'keep' da exclusão definitiva. Na mesclagem, os cards já foram para o contato que fica e não há o que limpar.
#
# Roda antes das outras dependências e dentro da transação do destroy: se algo falhar, o contato não sai. A exclusão em
# lote e o modo 'keep' cancelam as reuniões futuras antes, fora da transação (Crm::Cards::Anonimizador#cancelar_reunioes!);
# o DELETE contacts/:id e a exclusão da conta cancelam aqui (ContactsControllerCrmCards responde 422 se falhar).
#
# A FK crm_cards.contact_id é ON DELETE CASCADE: um DELETE em SQL, sem callbacks (Internal::RemoveStaleContactsService,
# que só pega contato sem card), apagaria os cards em vez de deixá-los com o dado pessoal.
module ContactCrmCards
  extend ActiveSupport::Concern

  included do
    before_destroy :anonimizar_cards_do_crm
  end

  private

  def anonimizar_cards_do_crm
    Crm::Cards::Anonimizador.new(contact: self).perform
  end
end
