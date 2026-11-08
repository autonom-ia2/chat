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
# CUSTO: no máximo uma por conversa a cada INTERVALO (SET NX no Redis). O aviso que chega dentro do intervalo não é
# descartado: fica UMA avaliação adiada para quando ele vence (a que chegar depois dela é lida por ela).
#
# O TURNO SEGUINTE EM CURSO (Autonomia::Agents::Operate::TurnoEmCurso): o cliente escreveu e o agente está respondendo
# (debounce, IA, pedaços). Entregar ali faria a resposta se perder. A avaliação volta depois (a espera cresce a cada
# tentativa e segura o intervalo), e o Evaluator confere isso antes de chamar o modelo. Passadas MAX_TENTATIVAS,
# desiste e deixa o evento.
#
# QUANDO NÃO AVALIA (as guardas do Evaluator#motivo_para_pular, a passagem não configurada, o teto de tentativas), o
# cliente ouviu "vou chamar alguém" e ninguém é chamado. Decisão do Rodrigo (24/10): sem funil ou sem passagem, a
# conversa fica com o agente até alguém da equipe pegar; sem fallback. Para não ser silencioso, fica a linha no log e o
# evento `atribuicao_nao_avaliou` do agente, com o motivo.
module Crm::Ai::AvaliacaoDepoisDaFala
  TRIGGER = 'fala_do_agente'.freeze
  # Uma avaliação da fala do agente por conversa neste intervalo.
  INTERVALO = 5.minutes
  CHAVE_DO_INTERVALO = 'crm:ai:fala_do_agente:%<conversa>d'.freeze
  # A avaliação adiada para o fim do intervalo: uma só.
  CHAVE_DA_ADIADA = 'crm:ai:fala_do_agente:adiada:%<conversa>d'.freeze
  # O turno seguinte em curso: volta depois de ESPERA × a tentativa (20 s, 40 s... 6 tentativas somam 7 minutos).
  ESPERA_DA_FALA_EM_CURSO = 20.seconds
  MAX_TENTATIVAS = 6

  module_function

  def agendar(conversation)
    return if conversation.blank? || !Crm::Ai::Config.enabled? || !Autonomia::Agents::AgenteSoInforma.ligada?(conversation.account)

    card = Crm::Assunto.funil_atual(conversation)
    motivo = motivo_para_nao_avaliar(card)
    return nao_avalia(conversation, card, motivo) if motivo

    espera = vez_no_intervalo(conversation)
    return registrar(conversation, card, 'ja_adiada') if espera.nil?

    Crm::Ai::EvaluateCardJob.set(wait: espera).perform_later(card.id, nil, TRIGGER)
    registrar(conversation, card, espera > debounce ? 'adiada_pelo_intervalo' : 'agendada')
  end

  def fala_em_curso?(conversation)
    Autonomia::Agents::Operate::TurnoEmCurso.em_curso?(conversation.id)
  end

  # O turno seguinte está em curso: a mesma avaliação volta depois, e o intervalo fica seguro até lá (um aviso novo
  # nesse meio tempo é adiado, não vira outra avaliação). Passado o teto, desiste com o evento.
  def reagendar(card, conversation, tentativa)
    proxima = tentativa.to_i + 1
    return nao_avalia(conversation, card, 'fala_em_curso') if proxima > MAX_TENTATIVAS

    espera = ESPERA_DA_FALA_EM_CURSO * proxima
    segurar_o_intervalo(conversation, espera)
    Crm::Ai::EvaluateCardJob.set(wait: espera).perform_later(card.id, nil, TRIGGER, proxima)
    registrar(conversation, card, "fala_em_curso tentativa=#{proxima}")
  end

  # As guardas do Evaluator (o mesmo método que a avaliação usa) e a passagem configurada na etapa ou no funil.
  def motivo_para_nao_avaliar(card)
    return 'sem_card' if card.nil?

    motivo = Crm::Ai::Evaluator.new(card: card, trigger: TRIGGER).motivo_para_pular
    return motivo if motivo
    return 'sem_passagem' unless Crm::Ai::Config.handoff_settings(card.stage, card.pipeline)[:enabled]

    nil
  end

  # -> a espera até avaliar: o debounce, fora do intervalo; o resto do intervalo, quando ninguém adiou ainda; nil quando
  # já há uma avaliação adiada para o fim dele (ela vai ler este aviso também).
  def vez_no_intervalo(conversation)
    return debounce if Redis::Alfred.set(chave(CHAVE_DO_INTERVALO, conversation), Time.current.to_i, nx: true, ex: INTERVALO.to_i)

    resto = [Redis::Alfred.ttl(chave(CHAVE_DO_INTERVALO, conversation)).to_i, 1].max.seconds
    return nil unless Redis::Alfred.set(chave(CHAVE_DA_ADIADA, conversation), Time.current.to_i, nx: true, ex: (resto + debounce).to_i)

    resto + debounce
  end

  def segurar_o_intervalo(conversation, espera)
    chave = chave(CHAVE_DO_INTERVALO, conversation)
    validade = [Redis::Alfred.ttl(chave).to_i, (espera + debounce).to_i].max
    Redis::Alfred.set(chave, Time.current.to_i, ex: validade)
  end

  def chave(modelo, conversation) = format(modelo, conversa: conversation.id)

  def debounce = Crm::Ai::Config::DEBOUNCE_SECONDS.seconds

  def nao_avalia(conversation, card, motivo)
    Autonomia::Agents::Operate::EventLogger.atribuicao_nao_avaliou(conversation: conversation, motivo: motivo)
    registrar(conversation, card, motivo)
  end

  def registrar(conversation, card, desfecho)
    Rails.logger.info("[crm][ai] fala_do_agente conversa=#{conversation.id} card=#{card&.id || '-'} desfecho=#{desfecho}")
    desfecho
  end
end
