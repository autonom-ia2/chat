# Caso do Decisor (#858) que ninguém resolveu em 2 dias: vence e não retoma mais a automação.
# Mover card ou mandar mensagem dias depois agiria fora de hora.
class Autonomia::Decisores::VencerJob < ApplicationJob
  queue_as :low

  def perform(decisao_id)
    decisao = Autonomia::DecisorDecisao.find_by(id: decisao_id)
    return unless decisao&.vencida_por_prazo?

    decisao.update!(status: 'vencida')
  end
end
