# De hora em hora (schedule.yml): o contratado com a base de outra versão (o deploy mudou um arquivo de `base/`, ou a
# semeadura falhou) entra na fila da semeadura. Só enfileira; quem confere de novo, sob a trava, é o `SemearBaseJob`.
# Fica de fora, em silêncio, a conta com o modelo desligado e a conta sem a própria chave de IA: a base só sai com a
# chave dela, e enfileirar a cada hora só encheria o log.
class Autonomia::Agents::Contratados::BaseEmDiaJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    aptas = {}
    desatualizados.includes(:account).find_each do |agente|
      # A aptidão depende do modelo (`disponivel?`): a chave do cache é conta e modelo, não só a conta.
      chave = [agente.account_id, agente.marca_do_contratado['modelo']]
      apta = aptas.fetch(chave) { aptas[chave] = conta_apta?(agente) }
      Autonomia::Agents::Contratados::SemearBaseJob.perform_later(agente.id) if apta
    end
  end

  private

  def desatualizados
    Autonomia::Agents::Agent.kept
                            .where("config->'#{Autonomia::Agents::Contratados::MARCA}'->>'modelo' IN (?)",
                                   Autonomia::Agents::Contratados::MODELOS.keys)
                            .where("config->>'#{Autonomia::Agents::Contratados::BASE_VERSAO}' IS DISTINCT FROM ?",
                                   Autonomia::Agents::Contratados::Base::VERSAO)
  end

  def conta_apta?(agente)
    Autonomia::Agents::Contratados.disponivel?(agente.account, agente.marca_do_contratado['modelo']) &&
      Autonomia::Agents::Contratados::Base.chave_da_conta(agente.account).present?
  end
end
