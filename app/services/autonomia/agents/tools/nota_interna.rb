# A NOTA INTERNA QUE A FERRAMENTA DEIXA PARA A EQUIPE NO FECHO DA EXECUÇÃO (chat#612, 23/09/2026).
#
# O texto vem da ferramenta (`Native::Base#nota_da_equipe`) e é para quem atende: vai como mensagem PRIVADA, que o
# cliente não recebe e que nenhum modelo lê (o histórico da Lia e o do CRM são só de mensagens públicas).
#
# UMA NOTA POR EXECUÇÃO: a mensagem carrega o id da execução (`CHAVE`), e a conferência é feita sob o lock da
# conversa. O retry do motor e o varredor não a duplicam.
class Autonomia::Agents::Tools::NotaInterna
  CHAVE = 'autonomia_nota_interna'.freeze

  # -> a nota criada, ou nil (sem texto, sem conversa, ou já postada).
  def self.postar(run, texto)
    conversation = run.conversation
    return if texto.blank? || conversation.blank?

    nota = nil
    conversation.with_lock { nota = criar(run, conversation, texto) unless postada?(run, conversation) }
    Rails.logger.info("[autonomia][tool] nota interna run=#{run.id}") if nota
    nota
  end

  # O `content_attributes` é `store` (texto serializado numa coluna json): `->>` não o lê. O `LIKE` é a peneira barata,
  # e quem decide é a comparação exata do atributo, como em `Evento#mensagem`.
  def self.postada?(run, conversation)
    conversation.messages.where(private: true).where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                .any? { |message| message.content_attributes.to_h[CHAVE].to_s == run.id.to_s }
  end

  def self.criar(run, conversation, texto)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: texto, message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: run.agent_inbox&.agent_bot_id,
        content_attributes: { 'autonomia_agent_id' => run.autonomia_agent_id, CHAVE => run.id.to_s }
      )
    ).perform
  end

  private_class_method :postada?, :criar
end
