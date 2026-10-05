# A dúvida do Decisor (#858) vai ao Guia. Seguro: a decisão vale, a automação retoma e o caso vira
# exemplo (origem guia). Inseguro, ou sem resposta do Guia: o caso espera uma pessoa por até 2 dias.
#
# O Guia leva segundos; nesse meio-tempo a pessoa pode ter resolvido o caso. Por isso a troca de status
# é reivindicada (só vale se ainda for `duvida`), e a retomada sai antes do exemplo: se o exemplo
# falhar, a automação já retomou.
class Autonomia::Decisores::DuvidaJob < ApplicationJob
  queue_as :medium

  def perform(decisao_id)
    decisao = Autonomia::DecisorDecisao.find_by(id: decisao_id)
    return unless decisao&.status == 'duvida'

    estado = Autonomia::Decisores::Estado.da_decisao(decisao)
    veredito = Autonomia::Decisores::Duvida.new(decisao).perguntar(estado)
    veredito.seguro ? decidir(decisao, veredito, estado) : esperar_pessoa(decisao, veredito.motivo)
  rescue Autonomia::Decisores::Duvida::Error => e
    esperar_pessoa(decisao, "o Guia não respondeu (#{e.message})")
  end

  private

  def decidir(decisao, veredito, estado)
    return unless decisao.reivindicar!(estava: 'duvida', status: 'decidida_pelo_guia', resposta: veredito.resposta, motivo: veredito.motivo)

    Autonomia::Decisores::Retomada.enfileirar(decisao)
    decisao.decisor.guardar_exemplo!(texto: estado.texto_do_exemplo, resposta: veredito.resposta, origem: 'guia',
                                     decisao_id: decisao.id)
  end

  def esperar_pessoa(decisao, motivo)
    return unless decisao.reivindicar!(estava: 'duvida', status: 'esperando_pessoa', motivo: motivo)

    Autonomia::Decisores::VencerJob.set(wait: Autonomia::DecisorDecisao::PRAZO_PESSOA).perform_later(decisao.id)
    # #935 — uma decisão parada esperando gente: o Guia mede já (só antecipa).
    Autonomia::Guide::Pulso.agora(decisao.account)
  end
end
