# F8.3 (#2499): a troca de quem atende a conversa, como gatilho. Dois gatilhos, como os do card (TrocaNoCard, G9):
# `conversa.responsavel_mudou` (a pessoa, `assignee_id`) e `conversa.time_mudou` (o time, `team_id`).
#
# De onde vem: os eventos assignee.changed e team.changed que a própria conversa despacha no commit
# (AssignmentHandler), por qualquer caminho (a tela, a ação em lote, a API, a atribuição automática, um passo). O
# evento traz o `previous_changes` da gravação: só a coluna da pessoa (ou do time) mudando conta. Trocar só o robô não
# é troca de pessoa; a conversa que nasce já atribuída não é troca, como o card que nasce.
#
# A marca leva o anterior: `conversa.responsavel_mudou:<conversa>:<anterior ou 0>:<instante do despacho em µs>`. A mesma
# troca entregue duas vezes (o EventDispatcherJob repete o instante) tem a mesma marca; a volta é outro fato. Quem
# cuidava antes ainda não vira valor da receita: nenhum termo pede (F6-F8-gatilhos.md, seção 2).
module Autonomia::Automacao::TrocaNaConversa
  RESPONSAVEL = 'conversa.responsavel_mudou'.freeze
  TIME = 'conversa.time_mudou'.freeze
  COLUNAS = { RESPONSAVEL => 'assignee_id', TIME => 'team_id' }.freeze

  module_function

  # `mudou`: o `changed_attributes` do evento (o previous_changes da conversa). `instante`: o do despacho.
  def comecar(conversa, tipo, mudou, instante)
    mudou = mudou.to_h.with_indifferent_access
    return if conversa.nil? || mudou.key?('id')

    antes, agora = mudou[COLUNAS.fetch(tipo)]
    return if antes == agora

    ::Autonomia::Automacao::Escuta.comecar(conversa, tipo, evento: marca(tipo, conversa, antes, instante))
  end

  def marca(tipo, conversa, anterior_id, instante) = "#{tipo}:#{conversa.id}:#{anterior_id.to_i}:#{instante.utc.iso8601(6)}"
end
