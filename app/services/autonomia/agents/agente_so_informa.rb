# O AGENTE SÓ INFORMA; A IA DE ATRIBUIÇÃO PASSA A CONVERSA (#2154, regra do Rodrigo de 24/10). Flag de conta
# `agente_so_informa`, lida nos dois lados:
#
# - Agentes (Operate::Responder#handoff_if_signaled): o sinal `should_handoff` da instrução vira só o registro do turno
#   (evento `avisou_que_chama_alguem`). O agente responde o que a instrução manda ("vou chamar alguém da equipe") e
#   continua atendendo; não chama o `bot_handoff!`. Depois que a fala sai (na hora, na entrega de uma mensagem só; no
#   último pedaço, na entrega em pedaços, Operate::ChunkedDeliveryJob), pede a avaliação da IA de Atribuição
#   (ContratoDoFunil.avaliar_depois_da_fala -> Crm::Ai::AvaliacaoDepoisDaFala).
# - CRM (Crm::Ai::HandoffExecutor): a avaliação com o gatilho da fala do agente não esbarra no bloqueio
#   `owned_by_our_agent` (#1673) e entrega pelo Crm::Entrega, com as regras de sempre.
#
# Fora: o evento da cotação (ResponderAoEvento), a porta de engajamento, a recuperação do Híbrido e as ações do dono.
# Desligada: tudo como antes.
module Autonomia::Agents::AgenteSoInforma
  FLAG = 'agente_so_informa'.freeze
  # Vai no meta da entrega em pedaços: o último pedaço deste turno pede a avaliação.
  META = 'avisou_que_chama_alguem'.freeze

  module_function

  def ligada?(account)
    account.present? && account.feature_enabled?(FLAG)
  end
end
