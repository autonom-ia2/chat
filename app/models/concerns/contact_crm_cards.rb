# LGPD (#2096): com a flag crm_arquivados ligada na conta, todo contato excluído deixa os cards do CRM sem dado pessoal
# (Crm::Cards::Anonimizador) e cancela as reuniões futuras deles, em vez de só soltá-los com título, descrição, campos,
# memória e textos da IA dentro. Vale para todo caminho que destrói o contato com callbacks: o DELETE contacts/:id, a
# exclusão em lote e o modo 'keep' da exclusão definitiva. Na mesclagem, os cards já foram para o contato que fica e não
# há o que limpar.
#
# Desligada (decisão do Rodrigo, 23/10), e na exclusão da conta inteira (Crm::ContatosSoltamCardsNaExclusaoDaConta), o
# callback não faz nada e o `dependent: :nullify` do Contact solta os cards, como na main.
#
# Roda antes das outras dependências e dentro da transação do destroy: se algo falhar, o contato não sai. A exclusão em
# lote e o modo 'keep' cancelam as reuniões futuras antes, fora da transação (Crm::Cards::Anonimizador#cancelar_reunioes!);
# o lote passa o mesmo anonimizador (crm_anonimizador), que soma as reuniões para a Auditoria. O DELETE contacts/:id
# cancela aqui (ContactsControllerCrmCards responde 422 se falhar).
#
# Auditoria (decisão do Rodrigo, 23/10): quem exclui o contato pode não ver os cards dele (uma função personalizada só com
# contact_delete, ou um agente fora do funil). A exclusão é permitida, e cada contato que tinha card anonimizado ou
# reunião cancelada grava uma linha na Auditoria da conta: quem fez, quantos cards e quantas reuniões, só ids e contagens
# (Crm::ExclusaoDefinitiva.auditar_contato_excluido!). O modo 'keep' já auditou antes e chega aqui sem card.
#
# O lead da Prospecção que é desta pessoa sai de vez, e o que recusou contato fica só com a prova da recusa (#2143,
# Autonomia::Prospecting::LeadsDoContatoExcluido); entram na mesma linha da Auditoria. O contato é travado primeiro, como
# no Crm::ExclusaoDefinitiva.travar_contato!: a conversão de um lead que o use espera, e os leads dos cards são lidos sob
# essa trava, antes de o anonimizador soltá-los.
#
# A FK crm_cards.contact_id é ON DELETE CASCADE: um DELETE em SQL, sem callbacks (Internal::RemoveStaleContactsService,
# que só pega contato sem card), apagaria os cards em vez de soltá-los.
module ContactCrmCards
  extend ActiveSupport::Concern

  included do
    before_destroy :anonimizar_cards_do_crm
    # Da exclusão em lote, que roda num job sem Current.user: o anonimizador que já cancelou as reuniões antes do
    # destroy, fora da transação, e quem pediu a exclusão.
    attr_accessor :crm_anonimizador, :crm_excluido_por
  end

  private

  def anonimizar_cards_do_crm
    return if Crm::Cards::Anonimizador.conta_saindo? || !Crm::Cards::Anonimizador.ligado?(account)

    Contact.where(id: id).lock.pluck(:id)
    leads = Autonomia::Prospecting::LeadsDoContatoExcluido.new(contact: self)
    anonimizador = crm_anonimizador || Crm::Cards::Anonimizador.new(contact: self)
    ids = anonimizador.perform
    auditar_exclusao_do_crm(ids, anonimizador, leads.perform)
  end

  def auditar_exclusao_do_crm(card_ids, anonimizador, leads)
    return if card_ids.empty? && anonimizador.reunioes_canceladas.empty? && leads.apagados.empty? && leads.minimizados.empty?

    Crm::ExclusaoDefinitiva.auditar_contato_excluido!(
      contact: self, user: crm_excluido_por || Current.user, card_ids: card_ids, anonimizador: anonimizador, leads: leads
    )
  end
end
