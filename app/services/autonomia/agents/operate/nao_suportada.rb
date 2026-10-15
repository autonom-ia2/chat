# chat#1489: a nossa IA não responde ao aviso de "mensagem não suportada" do WhatsApp quando a conta tem a flag
# `whatsapp_hybrid_recovery`. Para não ser silêncio sem rastro, toda vez que ela deixa de responder por isso fica um
# evento `skipped_*` do agente que responderia a conversa (o de `Operate.eligible_agent_inbox`; sem agente, nada):
# - `mensagem_nao_suportada`: o aviso chegou e não há recuperação em curso;
# - `recuperada_tarde`: o texto foi recuperado depois dos 2 minutos de espera e ninguém falou depois;
# - `recuperacao_falhou`: a recuperação falhou ou passou do prazo de 30 minutos;
# - `recuperacao_acordar_falhou`: a recuperação gravou, mas o que vem depois (chamar a IA, avisar) falhou.
# Nos casos `recuperada_tarde` e `recuperacao_falhou`, com a flag ligada, a conversa vai para as pessoas:
# - conversa resolvida: só o evento, não reabre;
# - alguém falou depois do aviso (o cliente, uma pessoa, a nossa IA respondendo a uma mensagem mais nova): evento e nota
#   privada, sem passar — a conversa já seguiu;
# - senão: passa pelo caminho de sempre (`bot_handoff!` sob o lock, com o espelho no comando, evento `handed_off`) e
#   deixa a nota privada para quem for atender.
module Autonomia::Agents::Operate::NaoSuportada
  NOTES = {
    'recuperacao_falhou' => 'conversations.messages.whatsapp.unsupported_handoff_note',
    'recuperada_tarde' => 'conversations.messages.whatsapp.unsupported_late_note'
  }.freeze
  # O motivo que vai ao `bot_handoff!` (Crm::Entrega grava o texto livre na marca da conversa).
  HANDOFF_MOTIVOS = { 'recuperacao_falhou' => 'recuperacao_falhou', 'recuperada_tarde' => 'recuperacao_tarde' }.freeze
  ERRORS = [ActiveRecord::ActiveRecordError].freeze

  module_function

  def ignorada(message)
    skip(message, 'mensagem_nao_suportada')
  end

  def tarde(message)
    passar(message, 'recuperada_tarde')
  end

  def falhou(message)
    passar(message, 'recuperacao_falhou')
  end

  def acordar_falhou(message)
    skip(message, 'recuperacao_acordar_falhou')
  end

  # -> o vínculo do agente que responderia, ou nil (sem agente: nada a registrar).
  def skip(message, reason)
    conversation = message.conversation
    agent_inbox = ::Autonomia::Agents::Operate.eligible_agent_inbox(conversation)
    return if agent_inbox.nil?

    ::Autonomia::Agents::Operate::EventLogger.skipped(agent: agent_inbox.agent, conversation: conversation, reason: reason)
    agent_inbox
  rescue *ERRORS => e
    track(e, message)
    nil
  end

  def passar(message, reason)
    agent_inbox = skip(message, reason)
    return if agent_inbox.nil? || !message.account.feature_enabled?(::WhatsappHybrid::UnsupportedRecovery::FEATURE)

    conversation = message.conversation
    return if conversation.resolved?
    return nota(conversation, agent_inbox, reason) if conversa_seguiu?(message)

    passar_para_pessoas(conversation, agent_inbox, reason)
  rescue *ERRORS => e
    track(e, message)
    nil
  end

  def conversa_seguiu?(message)
    ::WhatsappHybrid::RecoveryAiWake.contact_spoke_after?(message) || ::WhatsappHybrid::RecoveryAiWake.answered_after?(message)
  end

  def passar_para_pessoas(conversation, agent_inbox, reason)
    released = false
    conversation.with_lock do
      if ::Autonomia::Agents::Operate.espelho_no_comando?(conversation, agent_inbox)
        conversation.bot_handoff!(motivo: HANDOFF_MOTIVOS.fetch(reason))
        released = true
      end
    end
    return unless released

    ::Autonomia::Agents::Operate::EventLogger.handed_off(agent: agent_inbox.agent, conversation: conversation, result: nil,
                                                         reason: reason)
    nota(conversation, agent_inbox, reason)
  end

  def nota(conversation, agent_inbox, reason)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: I18n.with_locale(conversation.account.locale) { I18n.t(NOTES.fetch(reason)) }, message_type: 'outgoing',
        private: true, sender_type: 'AgentBot', sender_id: agent_inbox.agent_bot_id,
        content_attributes: { 'autonomia_agent_id' => agent_inbox.autonomia_agent_id }
      )
    ).perform
  end

  def track(error, message)
    ChatwootExceptionTracker.new(error, account: message&.account).capture_exception
    Rails.logger.warn("[autonomia][operate] nao_suportada_failed message=#{message&.id} #{error.class}")
  end
end
