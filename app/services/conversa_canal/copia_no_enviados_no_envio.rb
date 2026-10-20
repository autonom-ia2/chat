# Por cima do Email::SendOnEmailService (#1938, parte B): depois do envio por SMTP, agenda a cópia na pasta de enviados
# da conta do cliente (ConversaCanal::CopiaNoEnviadosJob). O envio não espera o IMAP e não muda.
module ConversaCanal::CopiaNoEnviadosNoEnvio
  private

  def send_via_smtp
    super
    ConversaCanal::CopiaNoEnviadosJob.agendar(message.reload)
  end
end
