# A PASSAGEM E A NOTA DA PAUSA (#3270): o agente contratado que responderia a conversa está pausado (os dias grátis
# acabaram e a conta não tem a liberação, `Contratados::Gratis`). O cliente não pode ficar sem resposta sem ninguém saber:
#
# - a conversa vai para a equipe pelo caminho de sempre do robô que passa (`bot_handoff!` com o motivo
#   `contratado_pausado`, sob a trava e só com o espelho no comando, como em `Operate::NaoSuportada`), e o evento
#   `handed_off` fica registrado. A entrega usa as regras de Atribuição de hoje: `Crm::Entrega::ParaIa.alvo` não devolve
#   a conversa ao agente que está passando, então ela vai para alguém da equipe (ou fica à espera de pessoa). Vale a cada
#   mensagem; depois da primeira, o espelho já não está no comando e nada se repete;
# - a equipe recebe uma mensagem PRIVADA, UMA vez por conversa (a marca `CHAVE` na própria nota): o cliente não recebe
#   nada e nenhum modelo lê. O texto é do catálogo do fork e não leva dado de ninguém.
#
# Só quando a conversa estava com o agente: sem pessoa atribuída e com o contrato inteiro do turno, menos a pausa
# (`Operate.vinculo_que_atenderia`). A trava da conversa e a marca seguram a nota em dobro: duas mensagens juntas do
# cliente, ou um retry do job, não a repetem.
class Autonomia::Agents::Contratados::AvisoDaPausa
  CHAVE = 'autonomia_contratado_pausado'.freeze
  MOTIVO = 'contratado_pausado'.freeze

  # -> true quando passou a conversa ou deixou a nota; false quando não havia o que fazer (o agente não está pausado, a
  # conversa não é dele, ou ela já foi passada e a nota já existe).
  def self.postar(conversation)
    return false if conversation.blank? || conversation.assignee_id.present?

    agent_inbox = ::Autonomia::Agents::Operate.vinculo_que_atenderia(conversation)
    return false unless agent_inbox && ::Autonomia::Agents::Contratados::Gratis.pausado?(agent_inbox.agent)

    passou, nota = passar_e_notar(conversation, agent_inbox)
    if passou
      ::Autonomia::Agents::Operate::EventLogger.handed_off(agent: agent_inbox.agent, conversation: conversation, result: nil,
                                                           reason: MOTIVO)
    end
    Rails.logger.info("[autonomia][contratados] pausa conv=#{conversation.id} agente=#{agent_inbox.agent.id} passou=#{passou} nota=#{nota.present?}")
    passou || nota.present?
  end

  # -> [passou, nota]. O lock relê a conversa: a passagem e a nota são decididas sobre o estado de agora.
  def self.passar_e_notar(conversation, agent_inbox)
    passou = false
    nota = nil
    conversation.with_lock do
      if ::Autonomia::Agents::Operate.espelho_no_comando?(conversation, agent_inbox)
        conversation.bot_handoff!(motivo: MOTIVO)
        passou = true
      end
      nota = criar(conversation, agent_inbox) unless postada?(conversation)
    end
    [passou, nota]
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

  private_class_method :passar_e_notar, :postada?, :criar
end
