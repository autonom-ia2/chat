# Os gatilhos da Automação livre num lugar só (#2499, F6). Cada entrada diz em quem a execução roda (`alvo`), de onde
# o gatilho vem (`origem`: o despacho de eventos ou a varredura de tempo) e como o evento vira a marca única da coluna
# `evento` da execução.
#
# A marca é o que impede o mesmo fato de abrir duas execuções: o EventDispatcherJob repete o evento, e o índice único
# (automacao_id, evento) do #2494 barra a segunda, mesmo depois de a primeira fechar. Evento sem id próprio usa o
# instante do despacho com microssegundos, nunca o segundo: reabrir e resolver no mesmo segundo são dois fatos.
#
# Acrescentar um gatilho: a entrada aqui, o tipo no esquema da receita, a frase (en e pt_BR) e, se for evento, o
# método do AutomacaoListener. A Partida, o Executor e a varredura não mudam.
module Autonomia::Automacao::Gatilhos
  Entrada = Data.define(:tipo, :alvo, :origem)

  LISTA = [
    Entrada.new(tipo: 'conversa.criada', alvo: 'Conversation', origem: :evento),
    Entrada.new(tipo: 'conversa.aberta', alvo: 'Conversation', origem: :evento),
    Entrada.new(tipo: 'conversa.resolvida', alvo: 'Conversation', origem: :evento),
    Entrada.new(tipo: 'mensagem.criada', alvo: 'Conversation', origem: :evento)
  ].index_by(&:tipo).freeze

  module_function

  def tipos = LISTA.keys

  def entrada(tipo) = LISTA[tipo.to_s]

  # O tipo do alvo (`Conversation`, `Crm::Card`, `Contact`) do gatilho; nil quando o tipo não existe.
  def alvo(tipo) = entrada(tipo)&.alvo

  # A marca de um evento do despacho sem id próprio: "conversa.aberta:<id>:<instante em µs, UTC>".
  def marca_do_despacho(tipo, registro, instante)
    "#{tipo}:#{registro.id}:#{instante.utc.iso8601(6)}"
  end
end
