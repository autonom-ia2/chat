# "Um turno, uma ordem" (#1606, ponto 1): o settle do ReplyJob espera o assunto ser decidido antes de responder.
#
# Só quando a regra única do CRM diz que este turno espera o assunto (`ordem_do_turno?`). Aí o settle lê o marco
# (até que mensagem o assunto foi decidido E o Sync aplicado): marco na mensagem do settle ou depois dela, segue; sem
# marco, espera mais um pouco, até o TETO contado da última mensagem da rajada; passado o teto, segue com o dono de
# agora e deixa o rastro `assunto_atrasou`. Quem responde NÃO é guardado entre as rodadas: o ReplyJob relê a cada uma.
#
# O teto conta de quando a mensagem ficou pronta, isto é, de quando o conteúdo chegou (#1637): a que o WhatsApp Híbrido
# recupera (#1489) traz o texto 15 a 60 s depois de criada e grava `content_attributes['hybrid_recovered_at']`
# (ISO8601). Vale o mais tarde entre o created_at e esse horário; ausente ou inválido, o created_at.
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
    mensagem = @conversation.messages.find_by(id: @message_id)
    return TETO.in_milliseconds.to_i if mensagem.nil?

    ((Time.current - pronta_em(mensagem)) * 1000).round
  end

  def pronta_em(mensagem)
    recuperada_em = Time.iso8601(mensagem.content_attributes.to_h['hybrid_recovered_at'].to_s)
    [mensagem.created_at, recuperada_em].max
  rescue ArgumentError
    mensagem.created_at
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
