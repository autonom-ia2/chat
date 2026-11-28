# Semeia a base oficial no agente contratado (#3211), fora do pedido de contratar: o embedding é chamada externa e
# paga, sempre com a chave da própria conta (`Base.chave_da_conta`). Sem nova tentativa do Sidekiq: a falha fica no log
# com o motivo curto (nunca a mensagem do provedor, que pode trazer um pedaço da chave), e o cron (`BaseEmDiaJob`) tenta
# de novo na hora seguinte, porque a versão não mudou.
class Autonomia::Agents::Contratados::SemearBaseJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  def perform(agent_id)
    agente = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
    return unless semeia?(agente)

    resultado = Autonomia::Agents::Contratados::Base.semear_se_preciso!(agente)
    return unless resultado.is_a?(String)

    # A base pela metade pagou o embedding: conta, para o cron parar no teto (`Base::TETO_DE_PARCIAIS`).
    Autonomia::Agents::Contratados::Base.anotar_parcial!(agent_id) if resultado == Autonomia::Agents::Contratados::Base::BASE_PARCIAL
    avisar_no_log(agent_id, resultado)
  rescue Autonomia::Agents::EmbeddingService::EmbeddingError => e
    avisar_no_log(agent_id, e.motivo)
  rescue Faraday::Error
    # O resto do Faraday (resposta cortada, por exemplo) escapa do serviço sem rótulo; a exceção crua não vai ao log.
    avisar_no_log(agent_id, 'rede')
  end

  private

  # Contratado e com o modelo liberado: a chave da conta é a `Base` quem confere, sob a trava, e devolve
  # `sem_chave_da_conta`. #3270: o agente pausado (dias grátis vencidos, sem a liberação) não ganha base nova: o embedding
  # é pago e a conta não está pagando. A base que já existe fica. Liberada a conta, o cron (`BaseEmDiaJob`) semeia na hora
  # seguinte.
  def semeia?(agente)
    return false if agente.nil? || !agente.contratado?

    Autonomia::Agents::Contratados.liberado?(agente.account, agente.marca_do_contratado['modelo']) &&
      !Autonomia::Agents::Contratados::Gratis.pausado?(agente)
  end

  def avisar_no_log(agent_id, motivo)
    Rails.logger.warn("[autonomia][contratados] base não semeada agente=#{agent_id} motivo=#{motivo}")
  end
end
