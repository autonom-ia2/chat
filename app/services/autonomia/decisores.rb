# Decisor (#858): a pergunta que a automação faz sobre uma conversa antes de seguir.
module Autonomia::Decisores
  # O nome do passo na automação. action_params: [decisor_id, chave_que_segue].
  PASSO = 'perguntar_ao_decisor'.freeze
  # Teto de perguntas ao Jev por conta e mês. O custo do Jev é nosso; acima disso a decisão fica
  # `sem_cota` e os passos seguintes não rodam (~US$ 0,55 por conta no mês, pelo custo medido).
  LIMITE_MENSAL = 5_000
end
