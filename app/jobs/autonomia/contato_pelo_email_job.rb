# Contato pelo e-mail recebido (#1813): completa o contato a partir do e-mail que chegou. Confere de novo a flag e a
# mensagem, porque entre o enfileirar e o rodar a flag pode ter sido desligada.
#
# Novas tentativas: no máximo 2 (attempts: 3 conta a primeira), e depois o bloco só registra — sem ele o erro voltaria
# ao Sidekiq, que tentaria mais 3 vezes (`:max_retries: 3` do config/sidekiq.yml). A nova tentativa não paga a IA de
# novo pelo mesmo e-mail (Freios#primeira_leitura?): só refaz o que falhou antes da chamada.
class Autonomia::ContatoPeloEmailJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: 30.seconds, attempts: 3 do |job, erro|
    Rails.logger.error("[autonomia][contato_pelo_email] desistiu message=#{job.arguments.first} erro=#{erro.class}")
  end

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless Autonomia::ContatoPeloEmail.email_do_cliente?(message) && Autonomia::ContatoPeloEmail.ligado?(message.account)

    Autonomia::ContatoPeloEmail::Completar.new(message).perform
  end
end
