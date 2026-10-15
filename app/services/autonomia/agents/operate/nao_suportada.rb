# chat#1489: a nossa IA não responde ao aviso de "mensagem não suportada" do WhatsApp (PR 0, decisão do Rodrigo). Para
# não ser silêncio sem rastro, toda vez que ela deixa de responder por isso fica um evento `skipped_*` do agente que
# responderia a conversa (o mesmo de `Operate.eligible_agent_inbox`; sem agente, nada a registrar):
# - `mensagem_nao_suportada`: o aviso chegou e não há recuperação (flag desligada, caixa sem WhatsApp API pronto, tipo
#   que não é mensagem nova);
# - `recuperada_tarde`: o texto foi recuperado depois dos 2 minutos de espera e ninguém falou depois;
# - `recuperacao_falhou`: a recuperação falhou ou passou do prazo de 30 minutos.
# Só no último caso, e só com a flag `whatsapp_hybrid_recovery` ligada, a conversa passa para as pessoas pelo caminho de
# sempre (`bot_handoff!` sob o lock, com o espelho no comando, e o evento `handed_off`), com uma nota privada para quem
# for atender olhar no celular. Flag desligada: só o evento, ninguém muda de rota. Nunca levanta.
module Autonomia::Agents::Operate::NaoSuportada
  NOTE_KEY = 'conversations.messages.whatsapp.unsupported_handoff_note'.freeze

  module_function

  def ignorada(message)
    skip(message, 'mensagem_nao_suportada')
  end

  def tarde(message)
    skip(message, 'recuperada_tarde')
  end

  def falhou(message)
    agent_inbox = skip(message, 'recuperacao_falhou')
    return if agent_inbox.nil? || !message.account.feature_enabled?(::WhatsappHybrid::UnsupportedRecovery::FEATURE)

    passar_para_pessoas(message.conversation, agent_inbox)
  end

  # -> o vínculo do agente que responderia, ou nil (sem agente: nada a registrar).
  def skip(message, reason)
    conversation = message.conversation
    agent_inbox = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)
    return if agent_inbox.nil?

    ::Autonomia::Agents::Operate::EventLogger.skipped(agent: agent_inbox.agent, conversation: conversation, reason: reason)
    agent_inbox
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] nao_suportada_skip_failed message=#{message&.id} #{e.class}")
    nil
  end

  def passar_para_pessoas(conversation, agent_inbox)
    released = false
    conversation.with_lock do
      if ::Autonomia::Agents::Operate.espelho_no_comando?(conversation, agent_inbox)
        conversation.bot_handoff!
        released = true
      end
    end
    return unless released

    ::Autonomia::Agents::Operate::EventLogger.handed_off(agent: agent_inbox.agent, conversation: conversation, result: nil,
                                                         reason: 'recuperacao_falhou')
    nota(conversation, agent_inbox)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] nao_suportada_handoff_failed conv=#{conversation&.id} #{e.class}")
    nil
  end

  def nota(conversation, agent_inbox)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: I18n.with_locale(conversation.account.locale) { I18n.t(NOTE_KEY) }, message_type: 'outgoing',
        private: true, sender_type: 'AgentBot', sender_id: agent_inbox.agent_bot_id,
        content_attributes: { 'autonomia_agent_id' => agent_inbox.autonomia_agent_id }
      )
    ).perform
  end
end
