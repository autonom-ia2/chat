# Quantas tarefas longas rodam ao mesmo tempo (#936): uma por conta e três na instalação inteira.
#
# A vaga é da tarefa enquanto ela anda (entre um lote e outro também) e vence sozinha se o processo
# morrer sem devolver: a validade é renovada a cada lote. A tarefa que não consegue vaga fica na fila.
module Autonomia::Guide::Tarefas::Semaforo
  POR_CONTA = 'autonomia:guide:tarefas:conta:'.freeze
  RODANDO = 'autonomia:guide:tarefas:rodando'.freeze
  TRAVA = 'autonomia:guide:tarefas:semaforo'.freeze
  TOTAL = 3
  VALIDADE = 3.minutes

  module_function

  # -> true quando a tarefa tem (ou renovou) a vaga.
  def entrar(tarefa)
    entrou = false
    Redis::LockManager.new.with_lock(TRAVA, 2) { entrou = reservar(tarefa.id.to_s, tarefa.account_id) }
    entrou
  end

  def sair(tarefa)
    Redis::Alfred.with { |redis| redis.zrem(RODANDO, tarefa.id.to_s) }
    Redis::Alfred.delete_if_equals("#{POR_CONTA}#{tarefa.account_id}", tarefa.id.to_s)
  end

  def reservar(id, account_id)
    agora = Time.current.to_f
    Redis::Alfred.zremrangebyscore(RODANDO, '-inf', agora)
    dono = Redis::Alfred.get("#{POR_CONTA}#{account_id}")
    return false if dono.present? && dono != id
    return false if Redis::Alfred.zscore(RODANDO, id).nil? && Redis::Alfred.zcard(RODANDO) >= TOTAL

    Redis::Alfred.set("#{POR_CONTA}#{account_id}", id, ex: VALIDADE.to_i)
    Redis::Alfred.zadd(RODANDO, agora + VALIDADE.to_i, id)
    true
  end
end
