# Memória das IAs (#1601): uma vez por dia, apaga o bilhete que ficou sem contato (rede de segurança do apagamento).
class Crm::Memoria::VarreduraJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    apagados = Crm::Memoria::Apagar.orfaos!
    return if apagados.zero?

    Rails.logger.warn("[crm][memoria][varredura] bilhetes_sem_contato=#{apagados}")
    ChatwootExceptionTracker.new(StandardError.new("[crm][memoria] bilhetes sem contato apagados: #{apagados}")).capture_exception
  end
end
