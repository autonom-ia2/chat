# Roda UM lote da revisão de conversas do Guia (#3158, B8b) e se reenfileira para o próximo.
#
# O estado mora no banco, não no job: o que morrer no meio é retomado pelo `RevisoesVigiaJob`, e a conversa já lida
# não é lida de novo. Erro inesperado para a revisão como `falhou`, sem perder o que já foi lido.
# Fila `low`: a revisão só lê e pode esperar o dia a dia; uma por conta e três na instalação (`Revisoes::Semaforo`).
class Autonomia::Guide::RevisaoJob < ApplicationJob
  queue_as :low

  REVISAO = ::Autonomia::Guide::Revisao
  SEMAFORO = ::Autonomia::Guide::Revisoes::Semaforo
  LOTE = ::Autonomia::Guide::Revisoes::Lote
  ENTRE_LOTES = 1.second
  NA_FILA = 15.seconds
  # Cobre um lote inteiro com folga; se o processo morrer, a trava vence sozinha.
  TRAVA = 2.minutes

  def perform(revisao_id)
    revisao = REVISAO.find_by(id: revisao_id)
    return unless revisao&.andando?

    Redis::LockManager.new.with_lock("autonomia:guide:revisao:#{revisao.id}", TRAVA.to_i) { rodar(revisao.reload) }
  end

  private

  def rodar(revisao)
    return unless revisao.andando?
    return self.class.set(wait: NA_FILA).perform_later(revisao.id) unless SEMAFORO.entrar(revisao)
    return SEMAFORO.sair(revisao) unless revisao.mudar!(REVISAO::ANDANDO, REVISAO::RODANDO, batimento_em: Time.current)
    return self.class.set(wait: ENTRE_LOTES).perform_later(revisao.id) if LOTE.new(revisao).rodar == LOTE::CONTINUAR

    SEMAFORO.sair(revisao)
  rescue StandardError => e
    falhar(revisao, e)
  end

  def falhar(revisao, erro)
    rastro = Array(erro.backtrace).first(5).join("\n")
    Rails.logger.error("[autonomia][guide][revisao] revisao=#{revisao.id} #{erro.class}: #{erro.message}\n#{rastro}")
    revisao.mudar!(REVISAO::ANDANDO, REVISAO::FALHOU, motivo: 'erro')
    SEMAFORO.sair(revisao)
  end
end
