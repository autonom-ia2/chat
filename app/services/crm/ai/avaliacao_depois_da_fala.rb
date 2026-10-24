# A AVALIAÇÃO DA IA DE ATRIBUIÇÃO DEPOIS DA FALA DO AGENTE (#2154, flag de conta `agente_so_informa`). O agente de IA
# avisou o cliente que vai chamar alguém (o sinal `should_handoff` da instrução) e continua atendendo; quem decide se
# passa, e para quem, é a IA de Atribuição, lendo a conversa com essa fala (Crm::Ai::ContextBuilder: papel
# `platform_agent`; o HANDOFF do Crm::Ai::ClassifierPrompt conta o que o atendente automático declarou).
#
# Quem chama: os Agentes, pelo Autonomia::Agents::ContratoDoFunil, quando a fala já saiu (na hora, na entrega de uma
# mensagem só; no último pedaço, na entrega em pedaços). Por isso a avaliação lê a fala inteira.
#
# Sem o token de agendamento do Crm::Ai::Observer, de propósito: o token deixaria velha a avaliação da mensagem do cliente
# que esperava a vez, e uma mensagem do cliente logo depois deixaria velha esta. As duas rodam; o gatilho `TRIGGER` é o
# que deixa o Crm::Ai::HandoffExecutor passar a conversa com o agente nosso no nome, e não é cortado pelo intervalo entre
# avaliações (Crm::Ai::Evaluator), porque a do cliente pode ter acabado de rodar.
#
# Só agenda onde a passagem está configurada (a regra da etapa ou do funil do card em foco): sem ela, a avaliação não
# passaria a conversa. Cada saída deixa uma linha (ids e rótulos, nunca texto).
module Crm::Ai::AvaliacaoDepoisDaFala
  TRIGGER = 'fala_do_agente'.freeze

  module_function

  def agendar(conversation)
    return if conversation.blank? || !Crm::Ai::Config.enabled? || !Autonomia::Agents::AgenteSoInforma.ligada?(conversation.account)

    card = Crm::Assunto.funil_atual(conversation)
    return registrar(conversation, nil, 'sem_card') if card.nil?
    return registrar(conversation, card, 'sem_passagem') unless Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)[:enabled]

    Crm::Ai::EvaluateCardJob.set(wait: Crm::Ai::Config::DEBOUNCE_SECONDS.seconds).perform_later(card.id, nil, TRIGGER)
    registrar(conversation, card, 'agendada')
  end

  def registrar(conversation, card, desfecho)
    Rails.logger.info("[crm][ai] fala_do_agente conversa=#{conversation.id} card=#{card&.id || '-'} desfecho=#{desfecho}")
    desfecho
  end
end
