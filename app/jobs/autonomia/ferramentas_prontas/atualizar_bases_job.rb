# #2858 F5 — a rodada das bases baixadas (config/schedule.yml, a cada 5 minutos). Depois do horário da stack, enfileira
# UMA base que passou da hora (`Importador.vencida?`: a diária, uma vez por dia; a mensal, do 28º dia em diante) e que
# ainda não tentou hoje. A próxima entra quando a anterior termina (`AtualizarBaseJob` chama esta rodada de novo): as
# bases nunca baixam ao mesmo tempo. A que falhou tenta de novo no dia seguinte, com a cópia anterior valendo até lá.
# Sem nenhuma conta com a flag das bases, não baixa nada.
#
# O HORÁRIO (UTC, "HH:MM") vem de AUTONOMIA_PRONTAS_BASES_HORARIO_UTC. Sem ele, cada stack tem o seu, tirado do próprio
# endereço (FRONTEND_URL), entre 10:00 e 11:55 (depois de as fontes publicarem o dia): as duas stacks não baixam no
# mesmo minuto.
class Autonomia::FerramentasProntas::AtualizarBasesJob < ApplicationJob
  queue_as :scheduled_jobs
  sidekiq_options retry: false

  HORARIO = 'AUTONOMIA_PRONTAS_BASES_HORARIO_UTC'.freeze
  INICIO = 10 * 60
  PASSOS = 24
  PASSO = 5

  def self.horario
    ENV.fetch(HORARIO, '').strip.presence || padrao_da_stack
  end

  def self.padrao_da_stack
    minutos = INICIO + (Zlib.crc32(ENV.fetch('FRONTEND_URL', '')) % PASSOS * PASSO)
    format('%<hora>02d:%<minuto>02d', hora: minutos / 60, minuto: minutos % 60)
  end

  def perform
    return unless na_hora? && Autonomia::FerramentasProntas::Bases.em_uso?

    proxima = Autonomia::FerramentasProntas::Bases.importadores.find { |importador| a_fazer?(importador) }
    Autonomia::FerramentasProntas::AtualizarBaseJob.perform_later(proxima.chave) if proxima
  end

  private

  def na_hora?
    Time.current.utc.strftime('%H:%M') >= self.class.horario
  end

  def a_fazer?(importador)
    estado = Autonomia::FerramentasProntas::Bases::Estado.de(importador.chave)
    importador.vencida?(estado) && estado.tentado_em&.utc&.to_date != Time.current.utc.to_date
  end
end
