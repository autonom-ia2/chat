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

  # A fala que avisou começou a sair (a mensagem única, ou o 1º pedaço): o registro do turno. `reason`: o código do
  # motivo (a allowlist do EventLogger). O EventLogger nunca levanta.
  def fala_comecou!(agent:, conversation:, reason:, message:)
    ::Autonomia::Agents::Operate::EventLogger.avisou_que_chama_alguem(agent: agent, conversation: conversation, reason: reason,
                                                                      message: message)
  end

  # A fala que avisou terminou de sair: a IA de Atribuição avalia (pelo ContratoDoFunil). Nunca derruba a entrega: a
  # falha vai ao log e ao rastreador de erros.
  def fala_terminou!(conversation)
    ::Autonomia::Agents::ContratoDoFunil.avaliar_depois_da_fala(conversation)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] aviso_de_passagem_falhou conv=#{conversation&.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
    nil
  end
end
