# A atribuição da entrega numa gravação só (#1454): pessoa no nome, robô fora, conversa aberta e as marcas de espera
# encerradas, tudo no mesmo save. Duas gravações na mesma transação (atribuir e depois "passar") faziam o after_commit
# ler só a última e perder o ASSIGNEE_CHANGED (sem aviso na tela, sem sincronizar o card).
#
# Só muda a conversa na memória; quem chama grava, com a linha travada.
module Crm::Entrega::Atribuicao
  module_function

  # false quando a pessoa não é da conta da conversa (id de outra conta gravado numa regra, pessoa que saiu) ou quando a
  # conversa está resolvida ou adiada: entregar não reabre conversa (só a pendente abre, como no serviço de sempre).
  def aplicar(conversation, pessoa)
    return false unless pode_receber?(conversation, pessoa)

    # A passagem do robô (ou a pendente, legado): "esperando resposta" conta a partir daqui, como no bot_handoff!.
    conversation.waiting_since ||= Time.current if conversation.ai_assignee.present? || conversation.pending?
    conversation.assignee = pessoa
    conversation.ai_assignee = nil
    conversation.status = :open if conversation.pending?
    conversation.end_bot_handoff_wait
    true
  end

  def pode_receber?(conversation, pessoa)
    return false if conversation.resolved? || conversation.snoozed?

    conversation.account.users.exists?(id: pessoa.id)
  end
end
