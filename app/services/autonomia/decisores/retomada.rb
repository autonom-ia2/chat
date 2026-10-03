# Uma decisão que estava parada (dúvida) recebeu resposta: cada regra que esperava por ela retoma pelo
# mesmo caminho do passo, o PerguntarJob, que agora encontra a decisão tomada e segue só se for a chave
# combinada daquela regra. `retomada: true` faz o job conferir de novo as condições da regra.
module Autonomia::Decisores::Retomada
  module_function

  # -> as regras reenfileiradas (vazio quando nenhuma esperava).
  def enfileirar(decisao)
    Array(decisao.esperas).map do |espera|
      Autonomia::Decisores::PerguntarJob.perform_later(espera['regra'], decisao.conversation_id, decisao.message_id,
                                                       espera['indice'], true)
    end
  end
end
