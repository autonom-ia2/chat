# #2858 F5 — a rodada das bases baixadas (config/schedule.yml, a cada 5 minutos). Depois do horário da stack, enfileira
# UMA base a fazer, na ordem de `Bases.importadores` (as diárias pequenas primeiro). A próxima entra quando a anterior
# termina (`AtualizarBaseJob` chama esta rodada de novo): as bases nunca baixam ao mesmo tempo. Sem nenhuma conta com a
# flag das bases, não baixa nada. A FAZER é a base:
#   - que passou da hora (`Importador.vencida?`: a diária, uma vez por dia; a mensal, do 28º dia em diante) e ainda não
#     tentou hoje;
#   - que tentou hoje e precisa de NOVA TENTATIVA, `NOVA_TENTATIVA` depois da última: a rodada morreu no meio (nem
#     atualizou nem registrou falha; as travas de quem morreu já venceram), ou falhou e é dos focos de queimada
#     (`NOVA_TENTATIVA_NO_DIA`); as outras que falharam esperam o dia seguinte;
#   - com `limpeza_pendente` há mais de `NOVA_TENTATIVA`: entra só para apagar a geração antiga, sem baixar.
#
# O HORÁRIO (UTC, "HH:MM") vem de AUTONOMIA_PRONTAS_BASES_HORARIO_UTC. Inválido: alerta uma vez por dia (Sentry e log)
# e vale o da stack. Sem ele, cada stack tem o seu, tirado do próprio endereço (FRONTEND_URL), entre 10:00 e 11:55 (depois
# de as fontes publicarem o dia): as duas stacks não baixam no mesmo minuto.
class Autonomia::FerramentasProntas::AtualizarBasesJob < ApplicationJob
  queue_as :scheduled_jobs
  sidekiq_options retry: false

  HORARIO = 'AUTONOMIA_PRONTAS_BASES_HORARIO_UTC'.freeze
  ALERTA_DO_HORARIO = 'autonomia:prontas:bases:horario_invalido'.freeze
  INICIO = 10 * 60
  PASSOS = 24
  PASSO = 5
  HORAS = 0..23
  MINUTOS = 0..59
  NOVA_TENTATIVA = 3.hours

  class << self
    # Minutos desde a meia-noite UTC em que a stack começa.
    def horario
      valor = ENV.fetch(HORARIO, '').strip
      return padrao_da_stack if valor.empty?

      em_minutos(valor) || horario_invalido
    end

    def padrao_da_stack
      INICIO + (Zlib.crc32(ENV.fetch('FRONTEND_URL', '')) % PASSOS * PASSO)
    end

    private

    # "10:47" e "9:05" -> minutos; o resto, nil.
    def em_minutos(valor)
      partes = valor.split(':')
      return if partes.size != 2

      hora, minuto = partes.map { |parte| Integer(parte, 10, exception: false) }
      (hora * 60) + minuto if HORAS.cover?(hora) && MINUTOS.cover?(minuto)
    end

    def horario_invalido
      alertar_horario_invalido if Redis::Alfred.set(ALERTA_DO_HORARIO, '1', nx: true, ex: 1.day.to_i)
      padrao_da_stack
    end

    def alertar_horario_invalido
      Sentry.capture_message("[autonomia][pronta] #{HORARIO} inválido", level: :warning) if ENV['SENTRY_DSN'].present? && defined?(Sentry)
      Rails.logger.warn("[autonomia][pronta] ALERTA horario_invalido: #{HORARIO} não é HH:MM (UTC); vale o horário da stack")
    end
  end

  def perform
    return unless na_hora? && Autonomia::FerramentasProntas::Bases.em_uso?

    proxima = Autonomia::FerramentasProntas::Bases.importadores.find { |importador| a_fazer?(importador) }
    Autonomia::FerramentasProntas::AtualizarBaseJob.perform_later(proxima.chave) if proxima
  end

  private

  def na_hora?
    agora = Time.current.utc
    (agora.hour * 60) + agora.min >= self.class.horario
  end

  def a_fazer?(importador)
    estado = Autonomia::FerramentasProntas::Bases::Estado.de(importador.chave)
    return limpeza_vencida?(estado) unless importador.vencida?(estado)
    return true if estado.tentado_em.nil? || estado.tentado_em.utc.to_date != Time.current.utc.to_date

    nova_tentativa?(importador, estado)
  end

  def nova_tentativa?(importador, estado)
    return false if estado.tentado_em > NOVA_TENTATIVA.ago

    morreu = [estado.atualizado_em, estado.falhou_em].compact.none? { |quando| quando >= estado.tentado_em }
    morreu || importador::NOVA_TENTATIVA_NO_DIA
  end

  def limpeza_vencida?(estado)
    estado.motivo_da_falha == Autonomia::FerramentasProntas::Bases::Importacao::LIMPEZA_PENDENTE &&
      estado.falhou_em.present? && estado.falhou_em <= NOVA_TENTATIVA.ago
  end
end
