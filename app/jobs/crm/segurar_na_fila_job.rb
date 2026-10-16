# #1593 — a passagem do robô ao agente de IA falhou depois do commit (ConversationBotHandoff#concluir_passagem): a
# conversa precisa da marca de segurar do motor de entrega (Crm::Entrega::Marca), senão a fila (HandoffDrainJob) não a
# vê e ela fica esperando pessoa para sempre. A passagem tenta marcar na hora (perform_now); se nem isso der, este job
# tenta de novo, com retry.
#
# Relida sob a trava: quem entrou nesse meio tempo (uma pessoa, o agente de IA, a resolução) vence, e nada é gravado.
class Crm::SegurarNaFilaJob < ApplicationJob
  queue_as :default
  FALHA = 'erro_na_passagem'.freeze

  retry_on StandardError, wait: 30.seconds, attempts: 5 do |job, erro|
    Rails.logger.error("[crm][entrega] segurar na fila desistiu conversa=#{job.arguments.first} #{Crm::SegurarNaFilaJob.para_log(erro)}")
  end

  def perform(conversation_id, motivo)
    conversa = Conversation.find_by(id: conversation_id)
    return if conversa.nil?

    conversa.with_lock do
      next unless conversa.awaiting_person? && !conversa.resolved?

      Crm::Entrega::Marca.marcar(conversa, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo, falha: FALHA)
      conversa.save!
    end
  end

  # O erro para o log: a classe, a mensagem sem segredo nem documento (CampaignImports::SafeLogMessage) e onde estourou.
  def self.para_log(erro)
    "erro=#{erro.class} mensagem=#{CampaignImports::SafeLogMessage.call(erro.message)} onde=#{Array(erro.backtrace).first}"
  end
end
