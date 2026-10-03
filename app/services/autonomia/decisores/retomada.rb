# Uma decisão que estava parada (dúvida) recebeu resposta: a automação retoma pelo mesmo caminho do
# passo, o PerguntarJob, que agora encontra a decisão tomada e segue só se for a chave combinada.
module Autonomia::Decisores::Retomada
  module_function

  def enfileirar(decisao)
    return if decisao.automation_rule_id.blank? || decisao.proximo_passo.blank?

    Autonomia::Decisores::PerguntarJob.perform_later(decisao.automation_rule_id, decisao.conversation_id,
                                                     decisao.message_id, decisao.proximo_passo - 1)
  end
end
