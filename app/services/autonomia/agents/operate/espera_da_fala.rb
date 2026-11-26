# QUANTO ESPERAR E QUANDO ENTRAR NA FILA (#3211). Duas decisões do turno do agente, ambas por opção do agente
# (ParidadeDaConversa), ambas ligadas por padrão em todo agente, menos na Lia:
#
# - `da_rajada` (P1, `conversa_espera_a_fala`): a espera do debounce. Desligada, é a janela de sempre
#   (Config.debounce_seconds_for). Ligada, é o fim previsto da fala anterior menos agora, preso entre ESPERA_MINIMA e
#   ESPERA_MAXIMA; sem fim previsto, ESPERA_MINIMA. Assim a pergunta junta toda a rajada que o cliente mandou enquanto o
#   agente ainda falava.
# - `na_fila?` (P2, `conversa_em_fila`): o turno novo deve esperar porque outro turno está falando. Só vale até o prazo
#   da marca do debounce (`at` + `espera_ms`) mais TETO_DA_FILA: passado isso o turno segue mesmo com a marca ocupada, para
#   uma marca presa nunca travar a conversa. Sem a marca do debounce, ou sem `at`, não há prazo, então nunca fila.
#   #3225 (flag `agente_le_no_meio_do_turno`): quando quem fala é um turno ANTERIOR a esta mensagem, ele pode tê-la lido
#   no meio e estar respondendo por ela (Operate::LeituraNoTurno; o que ele leu fica na memória dele, e daqui não se vê).
#   Então o prazo é o teto do turno (TurnoEmCurso.teto_do_turno), sem o corte de TETO_DA_FILA; quando a fala acaba, o
#   settle confere se ela foi respondida junto (ReplyJob#respondida_junto?) ou segue o caminho de sempre.
# - `janela_do_settle`: quanto dura a janela do settle de uma rajada já marcada. Uma regra só para todos que a medem.
module Autonomia::Agents::Operate::EsperaDaFala
  ESPERA_MINIMA = 1.second
  ESPERA_MAXIMA = 180.seconds
  INTERVALO_DA_FILA = 2.seconds
  TETO_DA_FILA = 150.seconds

  module_function

  def da_rajada(agent:, conversation_id:, inbox:, agora: Time.current)
    return ::Autonomia::Agents::Config.debounce_seconds_for(agent) unless ::Autonomia::Agents::ParidadeDaConversa.espera_a_fala?(agent, inbox)

    fim = ::Autonomia::Agents::Operate::FalaEmCurso.fim_previsto(conversation_id)
    return ESPERA_MINIMA if fim.blank?

    (fim - agora).clamp(ESPERA_MINIMA.to_f, ESPERA_MAXIMA.to_f).seconds
  end

  def na_fila?(agent:, conversation:, message_id:, agora: Time.current)
    return false unless ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent, conversation.inbox)
    return false unless ::Autonomia::Agents::Operate::FalaEmCurso.ocupada_por_outro?(conversation.id, message_id)

    prazo = prazo_da_fila(agent, conversation, message_id)
    prazo.present? && agora < prazo
  end

  # A JANELA DO SETTLE da rajada marcada: a espera que o gatilho gravou na marca do debounce (`espera_ms`) ou, na marca
  # sem ela (gravada antes do #3211, ou sem marca), a janela de sempre do agente (Config.debounce_seconds_for).
  # `com_a_fila`: soma TETO_DA_FILA quando o agente tem a fila ligada, porque o settle pode seguir esperando o turno em
  # curso até lá. Quem mede a janela usa esta regra: a fila (prazo_da_fila), o turno refeito (ReenfileirarTurno), o turno
  # em andamento (AgentInbox#turno_em_andamento?) e o silêncio do WAHA (Waha::RichNative::UnsupportedTurnJob). Com as
  # opções desligadas e a marca gravada pelo gatilho, é a janela de sempre (6 s na marca = 6 s do debounce).
  def janela_do_settle(agent:, marca:, inbox:, com_a_fila: false)
    espera_ms = marca.is_a?(Hash) ? marca['espera_ms'] : nil
    janela = espera_ms.nil? ? ::Autonomia::Agents::Config.debounce_seconds_for(agent) : (espera_ms.to_i / 1000.0).seconds
    com_a_fila && ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent, inbox) ? janela + TETO_DA_FILA : janela
  end

  # A MAIOR janela de espera que um turno do `agent` pode ter, para o teto do turno (TurnoEmCurso.teto_do_turno). Sem
  # agente ou com as opções desligadas, é a maior janela de debounce de sempre (Config::OPERATE_DEBOUNCE_MAX_SECONDS),
  # o mesmo valor de antes do #3211. Com `conversa_espera_a_fala`, cobre ESPERA_MAXIMA; com `conversa_em_fila`, soma
  # TETO_DA_FILA (o settle pode esperar o turno em curso até lá). Sem caixa (nil): o pior caso de qualquer caixa.
  def janela_maxima(agent)
    paridade = ::Autonomia::Agents::ParidadeDaConversa
    debounce = ::Autonomia::Agents::Config::OPERATE_DEBOUNCE_MAX_SECONDS
    janela = paridade.espera_a_fala?(agent, nil) ? [debounce, ESPERA_MAXIMA].max : debounce
    paridade.em_fila?(agent, nil) ? janela + TETO_DA_FILA : janela
  end

  # O instante em que a fila desiste: o `at` da marca do debounce mais a janela do settle com o teto da fila (ou o teto do
  # turno, quando quem fala pode ter lido esta mensagem). nil sem prazo.
  def prazo_da_fila(agent, conversation, message_id)
    marca = conversation.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
    return unless marca.is_a?(Hash) && marca['at'].present?

    inicio = Time.zone.at(marca['at'].to_f)
    return inicio + ::Autonomia::Agents::Operate::TurnoEmCurso.teto_do_turno(agent) if quem_fala_pode_ter_lido?(agent, conversation, message_id)

    inicio + janela_do_settle(agent: agent, marca: marca, inbox: conversation.inbox, com_a_fila: true)
  end
  private_class_method :prazo_da_fila

  # #3225: a fala é de um turno anterior a esta mensagem (a âncora dele é menor), com a leitura do meio do turno ligada.
  def quem_fala_pode_ter_lido?(agent, conversation, message_id)
    return false unless ::Autonomia::Agents::Operate::LeituraNoTurno.ligada?(agent, conversation)

    dono = ::Autonomia::Agents::Operate::FalaEmCurso.dono(conversation.id)
    dono.present? && dono.to_i < message_id.to_i
  end
  private_class_method :quem_fala_pode_ter_lido?
end
