# Memória das IAs (#1601): depois de gravada uma passagem (Crm::Passagem after_create_commit). O bilhete pelo código na
# hora; a tarefa de retomar quando a IA ou um robô passou para uma pessoa; e a IA para melhorar o bilhete.
# Idempotente: o bilhete só é gravado se não há; a tarefa é uma por conversa (índice único). A conciliação
# (ConciliacaoJob) refaz o que este job não fez.
class Crm::Memoria::PassagemJob < ApplicationJob
  queue_as :low

  def perform(passagem_id)
    passagem = Crm::Passagem.find_by(id: passagem_id)
    return if passagem.nil? || !Crm::Memoria.ativa?(passagem.conversation)

    Crm::Memoria::Bilhete.fallback!(passagem)
    Crm::Memoria::Compromissos.abrir_retomada!(conversation: passagem.conversation, origem: 'passagem', passagem: passagem) if
      Crm::Memoria::Compromissos.cria_tarefa?(passagem)
    Crm::Memoria::BilheteJob.perform_later(passagem.id)
  end
end
