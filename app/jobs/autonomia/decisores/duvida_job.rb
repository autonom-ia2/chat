# A dúvida do Decisor (#858) vai ao Guia. Seguro: a decisão vale, vira exemplo (origem guia) e a
# automação retoma. Inseguro, ou sem resposta do Guia: o caso espera uma pessoa por até 2 dias.
class Autonomia::Decisores::DuvidaJob < ApplicationJob
  queue_as :medium

  def perform(decisao_id)
    decisao = Autonomia::DecisorDecisao.find_by(id: decisao_id)
    return unless decisao&.status == 'duvida'

    estado = Autonomia::Decisores::Estado.new(conversation: decisao.conversation, message: decisao.message)
    veredito = Autonomia::Decisores::Duvida.new(decisao).perguntar(estado)
    veredito.seguro ? decidir(decisao, veredito, estado) : esperar_pessoa(decisao, veredito.motivo)
  rescue Autonomia::Decisores::Duvida::Error => e
    esperar_pessoa(decisao, "o Guia não respondeu (#{e.message})")
  end

  private

  def decidir(decisao, veredito, estado)
    decisao.update!(status: 'decidida_pelo_guia', resposta: veredito.resposta, motivo: veredito.motivo)
    decisao.decisor.guardar_exemplo!(texto: estado.texto_do_exemplo, resposta: veredito.resposta, origem: 'guia',
                                     decisao_id: decisao.id)
    Autonomia::Decisores::Retomada.enfileirar(decisao)
  end

  def esperar_pessoa(decisao, motivo)
    decisao.update!(status: 'esperando_pessoa', motivo: motivo)
    Autonomia::Decisores::VencerJob.set(wait: Autonomia::DecisorDecisao::PRAZO_PESSOA).perform_later(decisao.id)
  end
end
