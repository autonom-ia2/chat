# #2216 — Prepend em Conversation (config/initializers/reabrir_ao_escrever.rb). Reabre a conversa resolvida ou adiada
# sem chamar o rodízio da caixa: a troca de status para aberta aciona a atribuição automática quando não há ninguém
# no nome (AutoAssignmentHandler), e quem começa conversa responde, não assume (#2067), nem passa a outra pessoa.
# Os callbacks de status seguem todos (status_changed_at, "adiada até" limpo, eventos e atividade); só a atribuição
# automática desta troca fica de fora. Com Assignment V2, o job da fila da caixa ainda pode pegar a conversa aberta sem
# ninguém numa rodada disparada por outra conversa, como faz com qualquer aberta sem dono.
module Conversations::ReabrirSemRodizio
  # Começar conversa pela gaveta Nova conversa (criação ou mensagem com o sinal) numa caixa com "Reabrir a mesma
  # conversa": a resolvida ou adiada reabre; aberta ou pendente fica como está. A situação é conferida sob a trava da
  # conversa (quem chama está numa transação): dois envios ao mesmo tempo não reabrem duas vezes.
  def reabrir_ao_escrever!
    return unless inbox.lock_to_single_conversation?

    lock!
    return unless resolved? || snoozed?

    reabrir_sem_rodizio!
  end

  def reabrir_sem_rodizio!
    @reabrindo_sem_rodizio = true
    open!
  ensure
    @reabrindo_sem_rodizio = false
  end

  private

  def should_run_auto_assignment?
    return false if @reabrindo_sem_rodizio

    super
  end
end
