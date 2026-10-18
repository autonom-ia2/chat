# chat#1489: com a flag `whatsapp_hybrid_recovery` e uma recuperação em curso, a nossa IA não responde ao aviso de
# "mensagem não suportada" do WhatsApp (MessageListener). Para não ser silêncio sem rastro, quando a recuperação não
# termina em resposta da IA fica um evento `skipped_*` do agente que responderia a conversa (o de
# `Operate.eligible_agent_inbox`; sem agente, nada):
# - `recuperada_tarde`: o texto foi recuperado depois dos 2 minutos de espera e ninguém falou depois;
# - `recuperacao_falhou`: a recuperação falhou ou passou do prazo de 30 minutos;
# - `recuperacao_acordar_falhou` / `recuperacao_passagem_falhou`: a recuperação gravou, mas chamar a IA (ou passar a
#   conversa para as pessoas) falhou depois.
# Nos casos `recuperada_tarde` e `recuperacao_falhou`, com a flag ligada, a decisão é tomada sob o lock, sobre a
# conversa relida:
# - resolvida: só o evento, não reabre;
# - alguém falou depois do aviso (o cliente, uma pessoa, a nossa IA respondendo a uma mensagem mais nova): evento e nota
#   privada, sem passar — a conversa já seguiu;
# - espelho no comando: passa pelo caminho de sempre (`bot_handoff!` com o motivo, evento `handed_off`) e deixa a nota;
# - já esperando por pessoa (espelho fora do comando): só a nota, para quem for atender.
module Autonomia::Agents::Operate::NaoSuportada
  NOTES = {
    'recuperacao_falhou' => 'conversations.messages.whatsapp.unsupported_handoff_note',
    'recuperada_tarde' => 'conversations.messages.whatsapp.unsupported_late_note'
  }.freeze
  # O motivo que vai ao `bot_handoff!` (Crm::Entrega grava o texto livre na marca da conversa).
  HANDOFF_MOTIVOS = { 'recuperacao_falhou' => 'recuperacao_falhou', 'recuperada_tarde' => 'recuperacao_tarde' }.freeze
  ERRORS = [ActiveRecord::ActiveRecordError].freeze

  module_function

  def tarde(message)
    passar(message, 'recuperada_tarde')
  end

  def falhou(message)
    passar(message, 'recuperacao_falhou')
  end

  # A recuperação gravou e o que veio depois falhou (`recuperacao_acordar_falhou` ou `recuperacao_passagem_falhou`).
  def depois_de_gravar_falhou(message, reason)
    skip(message, reason)
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
    acao = decidir_sob_lock(message, conversation, agent_inbox, reason)
    return if acao == :nada

    if acao == :passou
      ::Autonomia::Agents::Operate::EventLogger.handed_off(agent: agent_inbox.agent, conversation: conversation, result: nil,
                                                           reason: reason)
    end
    nota(conversation, agent_inbox, reason)
  rescue *ERRORS => e
    track(e, message)
    nil
  end

  # -> :nada | :nota | :passou. O lock relê a conversa: o estado é o de agora, não o de quando a recuperação começou.
  def decidir_sob_lock(message, conversation, agent_inbox, reason)
    acao = :nada
    conversation.with_lock do
      acao = if conversation.resolved?
               :nada
             elsif conversa_seguiu?(message) || !::Autonomia::Agents::Operate.espelho_no_comando?(conversation, agent_inbox)
               :nota
             else
               conversation.bot_handoff!(motivo: HANDOFF_MOTIVOS.fetch(reason))
               :passou
             end
    end
    acao
  end

  def conversa_seguiu?(message)
    ::WhatsappHybrid::RecoveryAiWake.contact_spoke_after?(message) || ::WhatsappHybrid::RecoveryAiWake.answered_after?(message)
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
