# O QUE O LOG PODE DIZER SOBRE UMA FALHA DE ENVIO, e o que ele nunca diz.
#
# Em 20/09/2026 uma cotação real morreu e o log guardava só `motivo=unavailable`: a categoria sem
# a porta, e nenhuma linha para a falha comum. O diagnóstico virou um dia de arqueologia para
# descobrir que a informação existia e tinha sido descartada na borda.
#
# A regra que sobrou: rótulo NOSSO sempre, mensagem NUNCA. A mensagem de um erro do connector pode
# carregar texto do portal (`business_message`), e a de uma exceção de rede pode carregar a
# requisição assinada. `etiqueta` é `categoria/porta`, os dois de lista fechada nossa; o resto é o
# nome da classe. Este módulo existe para que essa regra tenha um lugar só — e um teste.
module Autonomia::Agents::Tools::TelemetriaDoEnvio
  def self.rotulo(erro)
    return erro.etiqueta if erro.respond_to?(:etiqueta)

    erro.class.name
  end

  def self.falha_do_start(run:, intencao:, o_que:, motivo:)
    Rails.logger.warn("[autonomia][tool][async] #{o_que} run=#{run.id} slug=#{run.slug} " \
                      "intencao=#{intencao} motivo=#{motivo}")
  end

  # A SEGUNDA PORTA DE RECUSA (entrega 6): a conferência do turno passou (ou caiu) e a validação
  # do `start` recusou. A ferramenta devolve handle com `recusa` (o motivo) — o contrato que `poll` já
  # reconhece — e é aqui, não nela, que se sabe a conversa e o agente. Registrar nunca derruba a
  # execução: o evento da recusa vale mais que a nossa linha de log.
  def self.recusa_do_start(run:, handle:)
    handle = handle.to_h.deep_stringify_keys if handle.is_a?(Hash)
    return unless handle.is_a?(Hash) && handle['recusa'].present?

    ::Autonomia::Agents::Tools::Recusa.registrar(handle['recusa'], slug: run.slug, conversa: run.conversation_id,
                                                                   agente: run.agent, faltando: handle['faltando'],
                                                                   onde: 'envio')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] registro de recusa falhou run=#{run.id} #{e.class}")
  end
end
