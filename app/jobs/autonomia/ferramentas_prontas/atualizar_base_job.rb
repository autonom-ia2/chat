# #2858 F5 — a importação de UMA base (`Bases::Importacao`), na fila baixa: o download grande (até ~160 MB) e o COPY não
# seguram as filas do atendimento. Uma base por vez em toda a plataforma (a trava `RODADA`): com outra importando, sai
# sem fazer nada, e a rodada seguinte tenta. Depois da trava, confere de novo se a base ainda está vencida (outra rodada
# pode ter acabado de atualizar); em dia e com `limpeza_pendente`, só limpa. Ao terminar, chama a rodada
# (`AtualizarBasesJob`) para a próxima base. A nova tentativa é da rodada (`AtualizarBasesJob#a_fazer?`), nunca do
# Sidekiq: a falha já guardou o motivo, mandou o alerta e deixou a cópia anterior valendo.
class Autonomia::FerramentasProntas::AtualizarBaseJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  RODADA = 'autonomia:prontas:bases:rodada'.freeze
  # Menor que a nova tentativa do dia (`AtualizarBasesJob::NOVA_TENTATIVA`): a trava de quem morreu já venceu.
  VALIDADE_DA_RODADA = 2.5.hours

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
    estado = Autonomia::FerramentasProntas::Bases::Estado.de(importador.chave)
    importacao = Autonomia::FerramentasProntas::Bases::Importacao
    return importacao.new(importador).call if importador.vencida?(estado)

    importacao.new(importador).limpar if estado.motivo_da_falha == importacao::LIMPEZA_PENDENTE
  end

  def travar
    @token = SecureRandom.hex(8)
    Redis::Alfred.set(RODADA, @token, nx: true, ex: VALIDADE_DA_RODADA.to_i) ? true : false
  end

  def destravar
    Redis::Alfred.delete(RODADA) if Redis::Alfred.get(RODADA) == @token
  end
end
