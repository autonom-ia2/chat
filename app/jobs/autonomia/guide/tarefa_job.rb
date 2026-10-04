# Roda UM lote de uma tarefa longa do Guia (#936) e se reenfileira para o próximo.
#
# O estado mora no banco, não no job: o que morrer no meio é retomado pelo `TarefasVigiaJob`, e o
# item `feito` nunca repete. Erro não descarta a tarefa: ela pausa com o motivo, e a pessoa decide.
# Fila própria (`guia_tarefas`), abaixo da prospecção, para uma tarefa grande não segurar as filas
# do dia a dia; 2 s entre lotes, uma por conta e três na instalação (`Tarefas::Semaforo`).
class Autonomia::Guide::TarefaJob < ApplicationJob
  queue_as :guia_tarefas

  SEMAFORO = ::Autonomia::Guide::Tarefas::Semaforo
  LOTE = ::Autonomia::Guide::Tarefas::Lote
  ENTRE_LOTES = 2.seconds
  NA_FILA = 15.seconds
  # Cobre um lote inteiro com folga; se o processo morrer, a trava vence sozinha.
  TRAVA = 2.minutes

  def perform(tarefa_id)
    tarefa = ::Autonomia::Guide::Tarefa.find_by(id: tarefa_id)
    return unless tarefa&.andando?

    trava = "autonomia:guide:tarefa:#{tarefa.id}"
    travas.with_lock(trava, TRAVA.to_i) { rodar(tarefa.reload) }
  end

  private

  def rodar(tarefa)
    return unless tarefa.andando?
    return self.class.set(wait: NA_FILA).perform_later(tarefa.id) unless SEMAFORO.entrar(tarefa)

    tarefa.update!(status: ::Autonomia::Guide::Tarefa::RODANDO, batimento_em: Time.current)
    return self.class.set(wait: ENTRE_LOTES).perform_later(tarefa.id) if LOTE.new(tarefa).rodar == LOTE::CONTINUAR

    SEMAFORO.sair(tarefa)
  rescue StandardError => e
    pausar_por_erro(tarefa, e)
  end

  def pausar_por_erro(tarefa, erro)
    Rails.logger.error("[autonomia][guide][tarefa] tarefa=#{tarefa.id} #{erro.class}: #{erro.message}\n#{Array(erro.backtrace).first(5).join("\n")}")
    tarefa.mudar!('pausar', motivo_pausa: 'erro')
    SEMAFORO.sair(tarefa)
  end

  def travas = Redis::LockManager.new
end
