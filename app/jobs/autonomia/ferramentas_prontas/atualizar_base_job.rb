# #2858 F5 — a importação de UMA base (`Bases::Importacao`), na fila baixa: o download grande (até ~160 MB) e o COPY não
# seguram as filas do atendimento. Uma base por vez em toda a plataforma (a trava `RODADA`): com outra importando, sai
# sem fazer nada, e a rodada seguinte tenta. Depois da trava, confere de novo se a base ainda está vencida (outra rodada
# pode ter acabado de atualizar). Ao terminar, chama a rodada (`AtualizarBasesJob`) para a próxima base. Sem nova
# tentativa automática: a falha já guardou o motivo, mandou o alerta e deixou a cópia anterior valendo.
class Autonomia::FerramentasProntas::AtualizarBaseJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  RODADA = 'autonomia:prontas:bases:rodada'.freeze
  VALIDADE_DA_RODADA = 4.hours

  def perform(chave)
    importador = Autonomia::FerramentasProntas::Bases.buscar(chave)
    return if importador.nil? || !Autonomia::FerramentasProntas::Bases.em_uso?
    return unless travar

    begin
      resultado = importar(importador)
    ensure
      destravar
    end
    # Ocupada (a trava da base ficou com quem morreu): não chama de novo, senão a mesma base voltaria em laço.
    Autonomia::FerramentasProntas::AtualizarBasesJob.perform_later unless resultado == :ocupada
  end

  private

  def importar(importador)
    return unless importador.vencida?(Autonomia::FerramentasProntas::Bases::Estado.de(importador.chave))

    Autonomia::FerramentasProntas::Bases::Importacao.new(importador).call
  end

  def travar
    @token = SecureRandom.hex(8)
    Redis::Alfred.set(RODADA, @token, nx: true, ex: VALIDADE_DA_RODADA.to_i) ? true : false
  end

  def destravar
    Redis::Alfred.delete(RODADA) if Redis::Alfred.get(RODADA) == @token
  end
end
