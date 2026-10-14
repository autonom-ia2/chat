# Pergunta ao modelo se a primeira resposta a uma campanha do WhatsApp foi pedido para parar (#1449). As regras ficam em
# CampaignJourney::OptOutReply; o job sai do ReplyMarkJob, depois que a mensagem da campanha já está na conversa.
#
# Provedor fora do ar ou resposta fora do schema: tenta de novo (três vezes, por uns minutos). Esgotado, ou sem chave de
# IA nenhuma (nem da conta nem da plataforma), o contato fica sem marca — na dúvida, não marca — e o log diz por quê,
# só com ids e a classe do erro.
class CampaignJourney::OptOutReplyJob < ApplicationJob
  queue_as :low

  retry_on Crm::Ai::ResponsesClient::Error, Crm::Ai::OptOutClassifier::InvalidAnswer,
           wait: :polynomially_longer, attempts: 3 do |job, error|
    job.log_failure('falhou', error)
  end

  discard_on Crm::Ai::OptOutClassifier::Unavailable do |job, error|
    job.log_failure(error.message, error)
  end

  def perform(message_id)
    message = Message.includes(:inbox, conversation: :contact).find_by(id: message_id)
    CampaignJourney::OptOutReply.new(message).perform if message
  end

  # Público: os blocos de `retry_on`/`discard_on` registram a falha por ele.
  def log_failure(status, error)
    Rails.logger.error("[campaign_journey][opt_out_reply] message=#{arguments.first} decisao=#{status} erro=#{error.class.name}")
  end
end
