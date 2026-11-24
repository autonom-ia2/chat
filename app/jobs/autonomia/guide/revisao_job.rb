# Roda UM lote da revisão de conversas do Guia (#3158, B8b) e se reenfileira para o próximo.
#
# O estado mora no banco, não no job: o que morrer no meio é retomado pelo `RevisoesVigiaJob`, e a conversa já lida
# não é lida de novo (`Revisao#avancar!`). Erro inesperado para a revisão como `falhou`, sem perder o que já foi
# lido; erro de infraestrutura (Redis, banco fora) volta para a fila do Sidekiq.
# Fila `low`: a revisão só lê e pode esperar o dia a dia; uma por conta e três na instalação (`Revisoes::Semaforo`).
#
# Uma cadeia por revisão. A trava cobre um lote; quem a encontra ocupada com batimento recente sabe que outra cadeia
# está viva e sai: ela, ao terminar, confere se a pessoa pediu "ler as que faltam" no meio e segue.
class Autonomia::Guide::RevisaoJob < ApplicationJob
  queue_as :low

  REVISAO = ::Autonomia::Guide::Revisao
  SEMAFORO = ::Autonomia::Guide::Revisoes::Semaforo
  LOTE = ::Autonomia::Guide::Revisoes::Lote
  VIGIA = ::Autonomia::Guide::RevisoesVigiaJob
  ENTRE_LOTES = 1.second
  NA_FILA = 15.seconds
  # Acima do pior lote: 20 s de lote mais uma conversa no prazo inteiro da IA (`Revisor::PRAZO`). Se o processo
  # morrer, a trava vence sozinha.
  TRAVA = 5.minutes
  INFRA = [Redis::BaseError, ActiveRecord::ConnectionNotEstablished].freeze

  def perform(revisao_id)
    revisao = REVISAO.find_by(id: revisao_id)
    return unless revisao&.andando?

    travou = Redis::LockManager.new.with_lock("autonomia:guide:revisao:#{revisao.id}", TRAVA.to_i) { rodar(revisao.reload) }
    # Ocupada e sem batimento recente: a outra cadeia morreu segurando a trava. Tenta de novo quando ela vencer.
    self.class.set(wait: NA_FILA).perform_later(revisao.id) if !travou && sem_batimento?(revisao.reload)
  end

  private

  def rodar(revisao)
    return unless revisao.andando?
    return esperar_vaga(revisao) unless SEMAFORO.entrar(revisao)
    return SEMAFORO.sair(revisao) unless revisao.mudar!(REVISAO::ANDANDO, REVISAO::RODANDO, batimento_em: Time.current)
    return seguir(revisao) if LOTE.new(revisao).rodar == LOTE::CONTINUAR

    SEMAFORO.sair(revisao)
    # A pessoa pode ter pedido "ler as que faltam" enquanto este lote terminava: a vez nova é desta cadeia.
    seguir(revisao) if revisao.reload.andando?
  rescue *INFRA
    raise
  rescue StandardError => e
    falhar(revisao, e)
  end

  # Sem vaga: espera na fila. O batimento diz ao vigia que esta cadeia está viva.
  def esperar_vaga(revisao)
    revisao.update_columns(batimento_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
    self.class.set(wait: NA_FILA).perform_later(revisao.id)
  end

  def seguir(revisao)
    self.class.set(wait: ENTRE_LOTES).perform_later(revisao.id)
  end

  def sem_batimento?(revisao)
    revisao.andando? && (revisao.batimento_em.nil? || revisao.batimento_em < VIGIA::SEM_BATIMENTO.ago)
  end

  # Só a classe e onde: a mensagem do erro pode trazer texto da conversa.
  def falhar(revisao, erro)
    rastro = Array(erro.backtrace).first(5).join("\n")
    Rails.logger.error("[autonomia][guide][revisao] revisao=#{revisao.id} #{erro.class}\n#{rastro}")
    revisao.mudar!(REVISAO::ANDANDO, REVISAO::FALHOU, motivo: 'erro')
    SEMAFORO.sair(revisao)
  end
end
