# Transcrição de uma conversa para a extração de FAQ (#284 · 2b). Cópia do desenho do Captain
# (ConversationFaqContentService): entram SÓ as mensagens públicas do CLIENTE e as respostas de um
# ATENDENTE HUMANO (User / eco externo). Respostas do próprio agente, notas privadas, automações e
# campanhas ficam de fora — a fonte de verdade da FAQ é o que o humano respondeu (o que o agente
# ainda não sabia). Cada resposta humana é prefixada com [m<id>] para o modelo citar a origem.
class Autonomia::Agents::Faq::Transcript
  MAX_MESSAGES = 200

  Result = Struct.new(:text, :human_message_ids, keyword_init: true)

  def initialize(conversation)
    @conversation = conversation
  end

  # -> Result (text vazio e ids [] quando não há resposta humana: nada a extrair, sem custo de IA).
  def build
    human_ids = []
    lines = messages.filter_map do |message|
      next unless source_message?(message)

      content = message.content_for_llm.to_s.strip
      next if content.blank?

      if human_reply?(message)
        human_ids << message.id
        "Atendente [m#{message.id}]: #{content}"
      else
        "Cliente: #{content}"
      end
    end

    Result.new(text: lines.join("\n"), human_message_ids: human_ids)
  end

  private

  def messages
    @conversation.messages
                 .where(message_type: %i[incoming outgoing], private: false)
                 .order(created_at: :asc)
                 .limit(MAX_MESSAGES)
  end

  def source_message?(message)
    return true if message.incoming? && message.sender_type == 'Contact'

    human_reply?(message)
  end

  def human_reply?(message)
    return false unless message.outgoing?
    return false if message.content_attributes.to_h['automation_rule_id'].present?
    return false if message.additional_attributes.to_h['campaign_id'].present?

    message.sender_type == 'User' || message.content_attributes.to_h['external_echo'].present?
  end
end
