# Ao apagar a conta inteira (DeleteObjectJob), cada contato sai com destroy!, e o ContactCrmCards (com a flag
# crm_arquivados) anonimizaria os cards e cancelaria as reuniões futuras de cada um no Google e na Microsoft, com aviso a
# cada cliente. Os cards saem junto com a conta: aqui os contatos só soltam os cards, como na main
# (Crm::Cards::Anonimizador.durante_exclusao_da_conta). Excluir uma caixa ou outro objeto segue igual.
#
# Só cuida dos contatos. Apagar a conta com cards do CRM ainda esbarra em chave estrangeira na main; isso é o #2134.
module Crm::ContatosSoltamCardsNaExclusaoDaConta
  def perform(object, *)
    return super unless object.is_a?(Account)

    Crm::Cards::Anonimizador.durante_exclusao_da_conta { super }
  end
end
