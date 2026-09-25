# A NOTA À EQUIPE NA HORA DA FALHA (decisão 3 do Rodrigo, 25/09/2026, chat#718; receita v3, R20).
#
# Par de `Tools::NotaInterna` (a nota do fecho de uma execução) e de `NotaDoEncaminhamento` (a da passagem à equipe),
# para a falha da cotação que não tem execução nem passagem: o especialista que gastou as seis rodadas sem abrir a
# cotação, a conferência em laço, a proposta em PDF de uma seguradora que não saiu. A Lia diz à pessoa, com a voz
# dela, que não deu; o motivo vai para quem atende, como mensagem PRIVADA, que o cliente não recebe e que nenhum
# modelo lê (o histórico da Lia e o do CRM são só de mensagens públicas).
#
# UMA NOTA POR CHAVE: quem posta diz a chave (a falha e o turno), ela vai no `content_attributes`, e a conferência é
# feita sob o lock da conversa. A mesma falha repetida no mesmo turno não vira duas notas.
#
# NUNCA LEVANTA: é cortesia sobre um caminho que já deu errado, e não pode derrubar o turno.
module Autonomia::Insurance::NotaNaHora
  CHAVE = 'autonomia_nota_na_hora'.freeze

  module_function

  # -> a nota criada, ou nil (sem texto, sem conversa, ou já postada).
  def postar(conversation, texto, chave:)
    return if texto.blank? || conversation.blank?

    # O lock é numa cópia lida agora: a conversa do turno pode ter atributos alterados em memória, e o Rails recusa
    # travar registro com mudança não gravada.
    conversa = conversation.class.find(conversation.id)
    nota = nil
    conversa.with_lock { nota = criar(conversa, texto, chave.to_s) unless postada?(conversa, chave.to_s) }
    Rails.logger.info("[autonomia][insurance] nota na hora conv=#{conversation.id}") if nota
    nota
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] nota_na_hora_falhou conv=#{conversation&.id} #{e.class}")
    nil
  end

  # O `content_attributes` é `store` (texto serializado): o `LIKE` é a peneira barata, e quem decide é a comparação
  # exata do atributo, como em `Tools::NotaInterna`.
  def postada?(conversation, chave)
    conversation.messages.where(private: true).where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                .any? { |message| message.content_attributes.to_h[CHAVE].to_s == chave }
  end

  def criar(conversation, texto, chave)
    agent_inbox = ::Autonomia::Agents::AgentInbox.find_by(inbox_id: conversation.inbox_id, account_id: conversation.account_id)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: texto, message_type: 'outgoing', private: true,
        sender_type: 'AgentBot', sender_id: agent_inbox&.agent_bot_id,
        content_attributes: { CHAVE => chave }
      )
    ).perform
  end

  private_class_method :postada?, :criar
end
