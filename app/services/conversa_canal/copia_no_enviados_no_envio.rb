# Por cima do Email::SendOnEmailService (#1938, parte B): depois do envio por SMTP, agenda a cópia na pasta de enviados
# da conta do cliente (ConversaCanal::CopiaNoEnviadosJob). O envio não espera o IMAP e não muda: o e-mail já saiu, e um
# erro ao agendar a cópia não pode chegar ao rescue do envio (marcaria a mensagem como falha e o atendente reenviaria).
module ConversaCanal::CopiaNoEnviadosNoEnvio
  private

  def send_via_smtp
    super
    agendar_copia_no_enviados
  end

  def agendar_copia_no_enviados
    ConversaCanal::CopiaNoEnviadosJob.agendar(message.reload)
  rescue StandardError => e
    Rails.logger.warn("[CopiaNoEnviados] não agendou a cópia da mensagem #{message.id}: #{e.class}")
  end
end
