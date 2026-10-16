# Multifunil 5/11 (#1145): a IA identifica de que assunto o cliente está falando.
#
# A cada mensagem recebida (com espera para juntar rajadas), o Jev escolhe entre: ainda não dá para saber, continua
# no assunto atual, voltou a um assunto aberto, ou é um pedido novo num funil da caixa. O modelo maior entra só na
# dúvida e quando é preciso dar nome ao assunto (o Jev só escolhe, não escreve). Na dúvida, nada muda.
# Nunca regex nem lista de palavras para interpretar o cliente (R17).
#
# Desligada por padrão (subject_ai_mode off): o admin liga caixa por caixa, em Sugerir ou Automática (#1260). Só funis
# com a IA do funil ligada (o mesmo interruptor da IA do card).
# Automática respeita a pessoa: o que ela acabou de escolher ou fechar vira sugestão, não troca sozinha.
module Crm::Subjects
  # Espera depois da última mensagem, como a avaliação de etapa: uma rajada vira uma pergunta só.
  DEBOUNCE = 15.seconds
  # Na ordem do turno (ordem_do_turno?), a espera é curta: o agente responde em ~6 s e espera o assunto até 20 s.
  DEBOUNCE_ORDEM = 3.seconds
  # Abaixo disso o Jev está em dúvida e o modelo maior decide.
  CERTEZA_MINIMA = 0.8
  # Teto de perguntas ao Jev por conta e mês (o custo do Jev é nosso).
  LIMITE_MENSAL = 10_000
  # Assuntos abertos que o Jev vê como opção; os mais recentes primeiro.
  MAX_ASSUNTOS = 8
  FEATURE = 'assunto'.freeze
  FEATURE_REVISAO = 'assunto_revisao'.freeze
  # A IA não troca sozinha o assunto que uma pessoa escolheu por este tempo: vira sugestão (#1260).
  RESPEITO_AO_FOCO = 4.hours
  # Card que a pessoa fechou ou arquivou não é recriado sozinho, e sugestão dispensada não volta, por este tempo.
  RESPEITO_AO_FECHAMENTO = 24.hours

  # A caixa aceita sugestão esperando uma pessoa: no modo Sugerir e também na Automática, que sugere em vez de agir
  # quando respeita a pessoa (#1260). Desligada, a sugestão perde o sentido (#1221).
  def self.sugerir?(conversation)
    Crm::InboxSetting.where(account_id: conversation.account_id, inbox_id: conversation.inbox_id, crm_enabled: true)
                     .where.not(subject_ai_mode: :off).exists?
  end

  # A IA do CRM está ligada na instalação e a caixa da conversa tem o CRM e a IA de assunto ligados.
  def self.ligado?(conversation)
    Crm::Ai::Config.enabled? && sugerir?(conversation)
  end

  # Pergunta o assunto da mensagem do cliente depois da espera, se a caixa tem a IA de assunto ligada. Um caminho só
  # para a mensagem nova (#1145) e para a recuperada pelo WhatsApp Híbrido (#1638). Na ordem do turno (#1606), fila
  # high e espera curta (DEBOUNCE_ORDEM): o agente espera o assunto antes de responder. Fora dela, fila low e DEBOUNCE.
  def self.identificar_depois(message)
    return unless message.incoming? && ligado?(message.conversation)

    # A regra do turno vai junto para o job: o Sync em linha segue a mesma decisão que escolheu a fila e a espera.
    ordem = ordem_do_turno?(message.conversation)
    job = if ordem
            Crm::Subjects::IdentifyJob.set(queue: :high, wait: DEBOUNCE_ORDEM)
          else
            Crm::Subjects::IdentifyJob.set(wait: DEBOUNCE)
          end
    job.perform_later(message.conversation_id, message.id, ordem)
  end

  # A REGRA ÚNICA de "este turno espera o assunto" (#1606, contrato com o Agentes IA, que só lê): a IA de assunto está
  # ligada na caixa, a Fase 2 dos Agentes está ligada na conta (linhas de responsável numa conta sem ela não contam), e a
  # caixa tem responsável por funil OU a conversa tem passagem em aberto. Verdadeira, a IA de assunto vai para a fila
  # high com espera de DEBOUNCE_ORDEM, troca o dono em linha (ResponsibleAgentSync) e só então grava o marco
  # (Crm::Subjects::Marco), que o ReplyJob espera. Falsa, nada muda: fila low, 15 s, Sync assíncrono, sem espera.
  # "Passagem em aberto" inclui a de pessoa → robô (o robô atende uma conversa que veio de uma pessoa): ali o assunto
  # ainda pode trocar o funil e o robô, então a ordem importa. Custo aceito pelo Multifunnel (15/10): fila high e espera
  # do marco nessas conversas, só com a Fase 2 ligada.
  def self.ordem_do_turno?(conversation)
    return false unless ligado?(conversation) && Crm::Ai::Config.areas_ligadas?(conversation.account)

    Crm::InboxAiAgent.exists?(account_id: conversation.account_id, inbox_id: conversation.inbox_id) ||
      Crm::Passagens.aberta?(conversation)
  end

  # O mesmo interruptor da IA do card: funil com a IA desligada fica fora da IA de assunto.
  def self.ia_do_funil?(pipeline)
    Crm::Ai::Config.pipeline_ai_settings(pipeline)[:enabled] != false
  end
end
