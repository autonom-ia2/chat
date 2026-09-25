# Estados da pesquisa, um por capacidade (empresa e decisor), espelho do Orth (lib/research/lead-capability-projection.ts)
# menos reconciling e insufficient_credits: aqui não há cobrança nem crédito (decisão do Rodrigo, #679).
module Autonomia::Prospecting::Research::States
  NOT_RESEARCHED = 'not_researched'.freeze
  QUEUED = 'queued'.freeze
  RESEARCHING = 'researching'.freeze
  WAITING_CAPACITY = 'waiting_capacity'.freeze
  TERMINAL = %w[confirmed possible ambiguous no_result failed blocked].freeze
  ALL = ([NOT_RESEARCHED, QUEUED, RESEARCHING, WAITING_CAPACITY] + TERMINAL).freeze
  # Pedido aceito e ainda não terminado: um segundo pedido do mesmo lead é recusado.
  IN_PROGRESS = [QUEUED, RESEARCHING, WAITING_CAPACITY].freeze
  # O job só roda o que está esperando: na fila ou esperando a vez da empresa.
  RUNNABLE = [QUEUED, WAITING_CAPACITY].freeze
end
