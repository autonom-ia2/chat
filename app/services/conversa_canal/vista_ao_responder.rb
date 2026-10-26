# Prepend em Message (#2202, PR 0): resposta nossa marca a conversa como vista até ela, como no WhatsApp ("se eu
# respondi, já li"). Antes, só abrir a conversa no painel gravava o "visto" (agent_last_seen_at, no update_last_seen do
# Api::V1::Accounts::ConversationsController). Quem respondia pelo celular (eco), o robô e a API nunca abriam a conversa
# no painel, e a bolinha de não lida ficava parada com a conversa já respondida.
#
# O que conta (VistaAoResponder.conta?): mensagem que sai (outgoing), pública, da pessoa pelo painel ou pela API, do
# eco do celular (com ou sem remetente), do robô, e o modelo do WhatsApp mandado na conversa (quem manda o modelo está
# respondendo nela, e no WhatsApp mandar qualquer coisa numa conversa a deixa lida).
# O que não conta: nota privada (o cliente não vê), campanha (disparo em massa: ninguém abriu a conversa, e no WhatsApp
# a lista de transmissão não marca a conversa como lida) e envio automático em nome de alguém (automação, follow-up,
# convite e aviso do Agendamento: Autonomia::Agents::Operate::PessoaDaEquipe.envio_automatico?). Mensagem automática da
# caixa (saudação, fora do horário, pesquisa) é `template`, não `outgoing`: já fica de fora. A importação do histórico
# não chega aqui (Message#execute_after_create_commit_callbacks sai antes).
#
# O "visto" vai até a hora da nossa mensagem, e nunca para trás: o eco atrasado de uma mensagem antiga não desfaz uma
# leitura mais nova. A mensagem do cliente que chegar depois volta a contar. Roda antes do `dispatch_create_events`
# original, para o message.created da resposta já levar a não lida zerada; e só avisa a tela (conversation.read, que só
# o ActionCable ouve) e os contadores quando havia não lida: resposta em sequência não refaz a contagem.
module ConversaCanal::VistaAoResponder
  def self.conta?(message)
    message.outgoing? && !message.private? && !::Autonomia::Agents::Operate::PessoaDaEquipe.envio_automatico?(message)
  end

  # -> true quando o "visto" andou.
  def self.marcar!(message)
    conversation = message.conversation
    momento = message.created_at
    havia_nao_lida = nao_lida_ate?(conversation, momento)
    agora = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    andou = Conversation.where(id: conversation.id).where(visto_antes_de(momento))
                        .update_all(agent_last_seen_at: momento, updated_at: agora).positive?
    # rubocop:enable Rails/SkipsModelValidations
    return false unless andou

    conversation.agent_last_seen_at = momento
    conversation.updated_at = agora
    conversation.clear_attribute_changes(%w[agent_last_seen_at updated_at])
    avisar(conversation) if havia_nao_lida
    true
  end

  def self.visto_antes_de(momento)
    visto = Conversation.arel_table[:agent_last_seen_at]
    visto.eq(nil).or(visto.lt(momento))
  end

  # Alguma mensagem do cliente entre o "visto" atual e a nossa resposta.
  def self.nao_lida_ate?(conversation, momento)
    recebidas = conversation.messages.where(account_id: conversation.account_id).incoming
                            .where(Message.arel_table[:created_at].lteq(momento))
    recebidas = recebidas.created_since(conversation.agent_last_seen_at) if conversation.agent_last_seen_at.present?
    recebidas.exists?
  end

  # Os mesmos avisos do "lido" ao abrir (ConversaCanal::LidoDaConversa) e o evento para a lista apagar a bolinha.
  def self.avisar(conversation)
    ::Conversations::UnreadCounts::Notifier.new(conversation).perform
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(conversation.account).conversation_changed!
    Rails.configuration.dispatcher.dispatch(Events::Types::CONVERSATION_READ, Time.zone.now, conversation: conversation)
  end

  private

  def dispatch_create_events
    marcar_conversa_vista
    super
  end

  # A mensagem já está gravada e o envio vem depois: falhar aqui não pode impedir o envio nem devolver erro a quem postou
  # (o n8n reenviaria e o cliente receberia duas vezes). A falha vai para o rastreador; a próxima resposta marca de novo.
  def marcar_conversa_vista
    return unless ConversaCanal::VistaAoResponder.conta?(self)

    ConversaCanal::VistaAoResponder.marcar!(self)
  rescue StandardError => e
    Rails.logger.error("[conversa][vista_ao_responder] conversa=#{conversation_id} mensagem=#{id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end
