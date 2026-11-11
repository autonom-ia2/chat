# O ALERTA DE BASE QUE NÃO ATUALIZOU (#2858, F5), no padrão do alerta operacional do proxy do WhatsApp
# (`WhatsappProxy::Alert`): é problema da PLATAFORMA, nunca da conta do cliente. Três canais:
#   - o log `[autonomia][pronta] ALERTA base=…`, sempre (como o `formato_mudou` da SUSEP na F4);
#   - o Sentry, quando a instalação tiver SENTRY_DSN;
#   - o aviso do Guia, urgente (sino, push e e-mail), para os administradores da conta da plataforma: a de
#     `AUTONOMIA_PRONTAS_ALERTA_CONTA_ID` ou, sem ela, a do alerta do proxy (`WHATSAPP_PROXY_ALERT_ACCOUNT_ID`). Sem
#     nenhuma das duas, só o log e o Sentry.
# Um aviso por base por dia (a chave do aviso leva o dia). O texto leva só a base, o motivo curto do código e desde
# quando a cópia que vale está lá: nada de endereço, arquivo ou mensagem de fora.
module Autonomia::FerramentasProntas::Bases::Alerta
  CONTA = 'AUTONOMIA_PRONTAS_ALERTA_CONTA_ID'.freeze
  CONTA_DO_PROXY = 'WHATSAPP_PROXY_ALERT_ACCOUNT_ID'.freeze

  module_function

  def falhou!(base, motivo, estado)
    desde = estado.atualizado_em&.utc&.to_date&.iso8601 || 'nunca'
    Rails.logger.warn("[autonomia][pronta] ALERTA base=#{base} motivo=#{motivo} vale_a_copia_de=#{desde}: a base não " \
                      'atualizou; a cópia anterior continua valendo')
    ao_sentry(base, motivo)
    a_plataforma(base, motivo, estado)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][pronta] alerta da base não enviado base=#{base} #{e.class}")
  end

  def ao_sentry(base, motivo)
    return if ENV['SENTRY_DSN'].blank? || !defined?(Sentry)

    Sentry.capture_message("[autonomia][pronta] base #{base}: #{motivo}", level: :warning, fingerprint: ['prontas_base', base, motivo])
  end

  def a_plataforma(base, motivo, estado)
    conta = Account.find_by(id: ENV.fetch(CONTA, '').presence || ENV.fetch(CONTA_DO_PROXY, '').presence)
    return if conta.nil?

    Autonomia::Guide::Entrega.new(conta).base_das_prontas!(base, motivo, estado.atualizado_em)
  end
end
