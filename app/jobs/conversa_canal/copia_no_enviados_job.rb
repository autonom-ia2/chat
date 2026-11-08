# Grava a cópia do e-mail enviado pelo painel na pasta de enviados da conta do cliente (#1938, parte B), fora do envio.
# Espera um pouco (ESPERA): o provedor que já guarda o que sai pelo SMTP dele tem tempo de pôr lá, e a cópia não dobra.
# - Caixa ocupada pela importação (lock da caixa): volta a tentar a cada ESPERA_DO_LOCK, até VOLTAS vezes.
# - Rede, timeout, IMAP ou OAuth: tenta de novo, pouco. Credencial recusada: desiste (quem decide a reautorização é a
#   importação). Desistir nunca é calado: log com a classe.
class ConversaCanal::CopiaNoEnviadosJob < ApplicationJob
  queue_as :low

  ESPERA = 2.minutes
  ESPERA_DO_LOCK = 30.seconds
  VOLTAS = 20
  TENTATIVAS = 3

  retry_on(*ConversaCanal::EmailLidoNoServidorJob::TRANSITORIOS, wait: 30.seconds, attempts: TENTATIVAS) do |job, error|
    job.desistir(error)
  end

  discard_on(ConversaCanal::ConexaoDoEmail::CredencialRecusada) do |job, error|
    job.desistir(error)
  end

  def self.agendar(message)
    return unless ConversaCanal::CopiaNoEnviados.aplica?(message)

    set(wait: ESPERA).perform_later(message)
  end

  def perform(message, voltas = 0)
    return unless ConversaCanal::CopiaNoEnviados.aplica?(message)

    resultado = ConversaCanal::CopiaNoEnviados.new(message).gravar
    Rails.logger.info("[conversa_canal][enviados] message=#{message.id} inbox=#{message.inbox_id} #{resultado}")
  rescue MutexApplicationJob::LockAcquisitionError => e
    return desistir(e) if voltas >= VOLTAS

    self.class.set(wait: ESPERA_DO_LOCK).perform_later(message, voltas + 1)
  end

  def desistir(error)
    message = arguments.first
    Rails.logger.warn("[conversa_canal][enviados] desistiu message=#{message&.id} #{error.class}")
  end
end
