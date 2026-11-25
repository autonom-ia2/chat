# Semeia a base oficial no agente contratado (#3211), fora do pedido de contratar: o embedding é chamada externa e
# paga. Sem nova tentativa do Sidekiq: a falha do provedor fica no log com o motivo curto (nunca a mensagem dele, que
# pode trazer um pedaço da chave), e o cron (`BaseEmDiaJob`) tenta de novo na hora seguinte, porque a versão não mudou.
class Autonomia::Agents::Contratados::SemearBaseJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(agent_id)
    agente = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
    return if agente.nil? || !agente.contratado?

    Autonomia::Agents::Contratados::Base.semear_se_preciso!(agente)
  rescue Autonomia::Agents::EmbeddingService::EmbeddingError => e
    Rails.logger.warn("[autonomia][contratados] base não semeada agente=#{agent_id} motivo=#{e.motivo}")
  end
end
