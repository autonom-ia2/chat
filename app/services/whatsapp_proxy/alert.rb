# Alerta operacional do proxy (#1516): plano esgotado, IP da fatia sumido, troca desfeita, sessão instável, quarentena,
# falha geral. São problemas da PLATAFORMA (comprar IP, ajustar fatia), nunca do cliente. Três canais:
# - log `[whatsapp_proxy][alerta]`, sempre (com o detalhe técnico);
# - aviso do Guia (o mesmo serviço do whatsapp_api_caiu!) para os administradores da conta da plataforma
#   WHATSAPP_PROXY_ALERT_ACCOUNT_ID — nunca para a conta do cliente; texto próprio em pt_BR/en, só com nº de caixa e
#   de conta, plano e IP mascarado (nada de telefone, nome ou credencial);
# - Sentry, quando a instalação tiver SENTRY_DSN.
# Limite de frequência: um alerta por código e assunto (sessão, IP ou plano; ou `subject:` explícito) por janela (1 h,
# ou `window:`) nos canais visíveis; o log fica.
module WhatsappProxy::Alert
  module_function

  THROTTLE = 1.hour.to_i

  # data: session:, ip:, pool:, count:, total:, date: — viram o texto do aviso já higienizados; subject: e window:
  # trocam o assunto e a janela do limite de frequência.
  def notify!(code, message, level: :warning, **data)
    Rails.logger.public_send(level == :error ? :error : :warn, "[whatsapp_proxy][alerta] #{code}: #{message}")
    subject = data[:subject] || data.values_at(:session, :ip, :pool, :date).compact.first
    return unless first_in_window?(code, subject, data.fetch(:window, THROTTLE))

    to_sentry(code, message, level)
    to_platform(code, level, data)
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_proxy] alerta não enviado (#{e.class})")
  end

  def first_in_window?(code, subject, window)
    ::Redis::Alfred.set("whatsapp_proxy:alert:#{code}:#{subject}", '1', nx: true, ex: window.to_i) ? true : false
  rescue Redis::BaseError
    true
  end

  def to_sentry(code, message, level)
    return if ENV['SENTRY_DSN'].blank? || !defined?(Sentry)

    Sentry.capture_message("[whatsapp_proxy] #{code}: #{message}", level: level, fingerprint: ['whatsapp_proxy', code])
  end

  def to_platform(code, level, data)
    account = Account.find_by(id: ENV.fetch('WHATSAPP_PROXY_ALERT_ACCOUNT_ID', '').presence)
    return if account.nil?

    Autonomia::Guide::Entrega.new(account).whatsapp_proxy!(code, details(data), urgente: level == :error)
  end

  def details(data)
    owner = data[:session] && WhatsappProxy::SessionOwner.find(data[:session])
    { caixa: owner&.inbox_id, conta: owner&.account_id, ip: mask(data[:ip]), plano: data[:pool], n: data[:count],
      total: data[:total], data: data[:date], horas: data[:hours] }.transform_values { |value| value.nil? ? '—' : value }
  end

  # "10.20.30.40:6000" → "10.20.x.x": dá para achar o IP no painel da Webshare sem expô-lo inteiro.
  def mask(ip)
    host = WhatsappProxy::Server.host(ip)
    return '—' if host.nil?

    "#{host.split('.').first(2).join('.')}.x.x"
  end
end
