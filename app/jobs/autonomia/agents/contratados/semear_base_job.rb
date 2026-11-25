# Semeia a base oficial no agente contratado (#3211), fora do pedido de contratar: o embedding é chamada externa e
# paga, sempre com a chave da própria conta (`Base.chave_da_conta`). Sem nova tentativa do Sidekiq: a falha fica no log
# com o motivo curto (nunca a mensagem do provedor, que pode trazer um pedaço da chave), e o cron (`BaseEmDiaJob`) tenta
# de novo na hora seguinte, porque a versão não mudou.
class Autonomia::Agents::Contratados::SemearBaseJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(agent_id)
    agente = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
    return if agente.nil? || !agente.contratado?
    return unless Autonomia::Agents::Contratados.disponivel?(agente.account, agente.marca_do_contratado['modelo'])

    resultado = Autonomia::Agents::Contratados::Base.semear_se_preciso!(agente)
    avisar_no_log(agent_id, resultado) if resultado.is_a?(String)
  rescue Autonomia::Agents::EmbeddingService::EmbeddingError => e
    avisar_no_log(agent_id, e.motivo)
  rescue Faraday::Error
    # O resto do Faraday (resposta cortada, por exemplo) escapa do serviço sem rótulo; a exceção crua não vai ao log.
    avisar_no_log(agent_id, 'rede')
  end

  private

  def avisar_no_log(agent_id, motivo)
    Rails.logger.warn("[autonomia][contratados] base não semeada agente=#{agent_id} motivo=#{motivo}")
  end
end
