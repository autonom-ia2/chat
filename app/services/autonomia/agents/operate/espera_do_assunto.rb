# "Um turno, uma ordem" (#1606, ponto 1): o settle do ReplyJob espera o assunto ser decidido antes de responder.
#
# Só quando a regra única do CRM diz que este turno espera o assunto (`ordem_do_turno?`). Aí o settle lê o marco
# (até que mensagem o assunto foi decidido E o Sync aplicado): marco na mensagem do settle ou depois dela, segue; sem
# marco, espera mais um pouco, até o TETO contado da última mensagem da rajada; passado o teto, segue com o dono de
# agora e deixa o rastro `assunto_atrasou`. Quem responde NÃO é guardado entre as rodadas: o ReplyJob relê a cada uma.
#
# Conta fora da Fase 2: nem pergunta ao CRM. O turno segue como sempre foi, sem leitura nenhuma a mais.
class Autonomia::Agents::Operate::EsperaDoAssunto
  TETO = 20.seconds
  INTERVALO = 3.seconds

  def self.esperar?(conversation:, agent_inbox:, message_id:)
    new(conversation, agent_inbox, message_id).esperar?
  end

  def initialize(conversation, agent_inbox, message_id)
    @conversation = conversation
    @agent_inbox = agent_inbox
    @message_id = message_id.to_i
  end

  def esperar?
    return false unless ::Autonomia::Agents::Fase2.ligada?(@conversation.account)
    return false unless contrato.ordem_do_turno?(@conversation)

    decorrido = decorrido_ms
    return seguir(:assunto_esperou, decorrido) if contrato.decidido_ate(@conversation.id).to_i >= @message_id
    return true if decorrido < TETO.in_milliseconds

    registrar_atraso(decorrido)
    false
  end

  private

  def contrato
    ::Autonomia::Agents::ContratoDoFunil
  end

  def seguir(evento, decorrido)
    telemetria.registrar(evento, conversation_id: @conversation.id, msg: @message_id, ms: decorrido)
    false
  end

  # Mensagem sumida conta como teto estourado: não há o que esperar.
  def decorrido_ms
    criada_em = @conversation.messages.where(id: @message_id).pick(:created_at)
    return TETO.in_milliseconds.to_i if criada_em.nil?

    ((Time.current - criada_em) * 1000).round
  end

  # Uma linha por turno; no painel do agente, um evento por conversa (a segunda vez não repete).
  def registrar_atraso(decorrido)
    seguir(:assunto_atrasou, decorrido)
    agent = @agent_inbox.agent
    return if agent.events.skipped_assunto_atrasou.exists?(conversation_id: @conversation.id)

    ::Autonomia::Agents::Operate::EventLogger.skipped(agent: agent, conversation: @conversation, reason: 'assunto_atrasou')
  end

  def telemetria
    ::Autonomia::Agents::Operate::TelemetriaDoTurno
  end
end
