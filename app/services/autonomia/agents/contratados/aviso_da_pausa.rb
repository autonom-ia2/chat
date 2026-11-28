# A NOTA DA PAUSA (#3270): o cliente escreveu e o agente contratado não respondeu porque está pausado (os dias grátis
# acabaram e a conta não tem a liberação, `Contratados::Gratis`). Quem fica sabendo é a equipe, numa mensagem PRIVADA, UMA
# vez por conversa (a marca `CHAVE` na própria nota): o cliente não recebe nada e nenhum modelo lê. O texto é do
# catálogo do fork e não leva dado de ninguém.
#
# Só quando a conversa estava com o agente: sem pessoa atribuída e com o contrato inteiro do turno, menos a pausa
# (`Operate.vinculo_que_atenderia`). A trava da conversa e a marca seguram a nota em dobro: duas mensagens juntas do
# cliente, ou um retry do job, não a repetem.
class Autonomia::Agents::Contratados::AvisoDaPausa
  CHAVE = 'autonomia_contratado_pausado'.freeze

  # -> a nota criada, ou nil (o agente não está pausado, a conversa não é dele, ou a nota já existe).
  def self.postar(conversation)
    return if conversation.blank? || conversation.assignee_id.present?

    agent_inbox = ::Autonomia::Agents::Operate.vinculo_que_atenderia(conversation)
    return unless agent_inbox && ::Autonomia::Agents::Contratados::Gratis.pausado?(agent_inbox.agent)

    nota = nil
    conversation.with_lock { nota = criar(conversation, agent_inbox) unless postada?(conversation) }
    Rails.logger.info("[autonomia][contratados] nota da pausa conv=#{conversation.id} agente=#{agent_inbox.agent.id}") if nota
    nota
  end

  # O `content_attributes` é JSON dentro de texto em produção: a busca é por texto, e a marca é conferida no hash.
  def self.postada?(conversation)
    conversation.messages.where(private: true).where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                .any? { |mensagem| mensagem.content_attributes.to_h[CHAVE].present? }
  end

  def self.criar(conversation, agent_inbox)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: I18n.with_locale(conversation.account.locale) { I18n.t('autonomia.contratados.pausado.nota') },
        message_type: 'outgoing', private: true, sender_type: 'AgentBot', sender_id: agent_inbox.agent_bot_id,
        content_attributes: { CHAVE => true }
      )
    ).perform
  end

  private_class_method :postada?, :criar
end
