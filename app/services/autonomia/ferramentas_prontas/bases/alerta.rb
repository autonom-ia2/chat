# O ALERTA DE BASE QUE NÃO ATUALIZOU (#2858, F5). Decisão do Rodrigo (11/11): "Deixa no log". Dois canais, nesta ordem:
#   - o Sentry, quando a instalação tiver SENTRY_DSN (um agrupamento por base e motivo);
#   - o log `[autonomia][pronta] ALERTA base=…`, sempre (como o `formato_mudou` da SUSEP na F4).
# Nada vai para conta de cliente nem para o Guia. O texto leva só a base, o motivo curto do código e desde quando a
# cópia que vale está lá: nada de endereço, arquivo ou mensagem de fora.
module Autonomia::FerramentasProntas::Bases::Alerta
  module_function

  def falhou!(base, motivo, estado)
    ao_sentry(base, motivo)
    desde = estado.atualizado_em&.utc&.to_date&.iso8601 || 'nunca'
    Rails.logger.warn("[autonomia][pronta] ALERTA base=#{base} motivo=#{motivo} vale_a_copia_de=#{desde}: a base não " \
                      'atualizou; a cópia anterior continua valendo')
  end

  def ao_sentry(base, motivo)
    return if ENV['SENTRY_DSN'].blank? || !defined?(Sentry)

    Sentry.capture_message("[autonomia][pronta] base #{base}: #{motivo}", level: :warning, fingerprint: ['prontas_base', base, motivo])
  rescue StandardError => e
    Rails.logger.warn("[autonomia][pronta] alerta da base não foi ao Sentry base=#{base} #{e.class}")
  end
end
