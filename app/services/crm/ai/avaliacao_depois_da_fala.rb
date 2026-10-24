# A AVALIAÇÃO DA IA DE ATRIBUIÇÃO DEPOIS DA FALA DO AGENTE (#2154, flag de conta `agente_so_informa`). O agente de IA
# avisou o cliente que vai chamar alguém (o sinal `should_handoff` da instrução) e continua atendendo; quem decide se
# passa, e para quem, é a IA de Atribuição, lendo a conversa com essa fala (Crm::Ai::ContextBuilder: papel
# `platform_agent`; o HANDOFF do Crm::Ai::ClassifierPrompt conta o que o atendente automático declarou).
#
# Quem chama: os Agentes, pelo Autonomia::Agents::ContratoDoFunil, quando a fala já saiu (na hora, na entrega de uma
# mensagem só; no último pedaço, ou quando o cliente escreveu depois de algum pedaço, na entrega em pedaços).
#
# É uma avaliação SÓ DE PASSAGEM (Crm::Ai::Evaluator#so_a_passagem): lê a conversa e decide a passagem; não move etapa,
# não grava campo, memória, pontuação nem o carimbo da última avaliação. Por isso não derruba, pelo intervalo entre
# avaliações, a avaliação da mensagem do cliente, e também não é derrubada por ela. Sem o token de agendamento do
# Crm::Ai::Observer, de propósito: ele deixaria velha a avaliação do cliente que esperava a vez.
#
# Custo: no máximo uma por conversa a cada INTERVALO (SET NX no Redis). Antes de agendar, as mesmas guardas do
# Evaluator#motivo_para_pular (IA do funil, credencial, card aberto e em foco) e a passagem configurada. Quando não
# agenda por uma delas, o cliente ouviu "vou chamar alguém" e ninguém vem: fica a linha no log e o evento
# `atribuicao_nao_avaliou` do agente, com o motivo, para aparecer. O que fazer nesses casos é decisão em aberto do
# Rodrigo (#2154).
module Crm::Ai::AvaliacaoDepoisDaFala
  TRIGGER = 'fala_do_agente'.freeze
  # Uma avaliação da fala do agente por conversa neste intervalo. O aviso repetido logo em seguida (o cliente insiste)
  # não paga outra leitura; passado o intervalo, um aviso novo é avaliado de novo.
  INTERVALO = 5.minutes
  CHAVE_DO_INTERVALO = 'crm:ai:fala_do_agente:%<conversa>d'.freeze
  # A fala do turno seguinte ainda está saindo (Autonomia::Agents::Operate::CadeiaEmCurso): tenta de novo depois disto.
  ESPERA_DA_FALA_EM_CURSO = 20.seconds

  module_function

  def agendar(conversation)
    return if conversation.blank? || !Crm::Ai::Config.enabled? || !Autonomia::Agents::AgenteSoInforma.ligada?(conversation.account)

    card = Crm::Assunto.funil_atual(conversation)
    motivo = motivo_para_nao_avaliar(card)
    return nao_avalia(conversation, card, motivo) if motivo
    return registrar(conversation, card, 'intervalo') unless primeira_no_intervalo?(conversation)

    Crm::Ai::EvaluateCardJob.set(wait: Crm::Ai::Config::DEBOUNCE_SECONDS.seconds).perform_later(card.id, nil, TRIGGER)
    registrar(conversation, card, 'agendada')
  end

  # A fala do turno seguinte está saindo: a avaliação volta depois, fora do intervalo (é a mesma avaliação, adiada).
  def fala_em_curso?(conversation)
    Autonomia::Agents::Operate::CadeiaEmCurso.em_curso?(conversation.id)
  end

  def reagendar(card)
    Crm::Ai::EvaluateCardJob.set(wait: ESPERA_DA_FALA_EM_CURSO).perform_later(card.id, nil, TRIGGER)
  end

  # As guardas do Evaluator (o mesmo método que a avaliação usa) e a passagem configurada na etapa ou no funil.
  def motivo_para_nao_avaliar(card)
    return 'sem_card' if card.nil?

    motivo = Crm::Ai::Evaluator.new(card: card, trigger: TRIGGER).motivo_para_pular
    return motivo if motivo
    return 'sem_passagem' unless Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)[:enabled]

    nil
  end

  def primeira_no_intervalo?(conversation)
    Redis::Alfred.set(format(CHAVE_DO_INTERVALO, conversa: conversation.id), Time.current.to_i, nx: true, ex: INTERVALO.to_i)
  end

  def nao_avalia(conversation, card, motivo)
    Autonomia::Agents::Operate::EventLogger.atribuicao_nao_avaliou(conversation: conversation, motivo: motivo)
    registrar(conversation, card, motivo)
  end

  def registrar(conversation, card, desfecho)
    Rails.logger.info("[crm][ai] fala_do_agente conversa=#{conversation.id} card=#{card&.id || '-'} desfecho=#{desfecho}")
    desfecho
  end
end
