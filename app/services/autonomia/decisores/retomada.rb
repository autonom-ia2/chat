# Uma decisão que estava parada (dúvida) recebeu resposta: cada automação que esperava por ela retoma
# pelo mesmo caminho do passo — o PerguntarJob (regra de automação) ou o PerguntarEtapaJob (automação de
# etapa do CRM) —, que agora encontra a decisão tomada e segue só se for a chave combinada daquela
# automação. `retomada: true` faz o job conferir de novo se ela ainda vale (condições da regra, card
# ainda na etapa).
module Autonomia::Decisores::Retomada
  module_function

  # -> as automações reenfileiradas (vazio quando nenhuma esperava).
  def enfileirar(decisao)
    Array(decisao.esperas).map do |espera|
      next Autonomia::Decisores::PerguntarEtapaJob.perform_later(espera['execucao'], espera['etapa'], true) if espera['etapa']

      Autonomia::Decisores::PerguntarJob.perform_later(espera['regra'], decisao.conversation_id, decisao.message_id,
                                                       espera['indice'], true)
    end
  end
end
