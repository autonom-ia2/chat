# Alerta operacional do proxy (#1516): plano esgotado, IP da fatia sumido, troca desfeita, sessão instável, quarentena.
# São problemas da plataforma (comprar IP, ajustar fatia), não do cliente: vão para o Sentry da instalação (mesmo canal
# dos erros, agrupados por código) e para o log. O aviso do Guia (DownAlert) fala com o administrador da conta e não
# serve aqui. A mensagem nunca leva credencial: só sessão, IP:porta e plano.
module WhatsappProxy::Alert
  module_function

  def notify!(code, message, level: :warning)
    Rails.logger.public_send(level == :error ? :error : :warn, "[whatsapp_proxy][alerta] #{code}: #{message}")
    return if ENV['SENTRY_DSN'].blank? || !defined?(Sentry)

    Sentry.capture_message("[whatsapp_proxy] #{code}: #{message}", level: level, fingerprint: ['whatsapp_proxy', code])
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_proxy] alerta não enviado (#{e.class})")
  end
end
