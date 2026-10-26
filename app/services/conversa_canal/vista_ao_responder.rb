# Prepend em Message (#2202, PR 0): resposta de uma PESSOA marca a conversa como vista, como no WhatsApp ("se eu
# respondi, já li"). Antes, só abrir a conversa no painel gravava o "visto" (agent_last_seen_at, no update_last_seen do
# Api::V1::Accounts::ConversationsController); quem respondia pela API com token de pessoa nunca abria a conversa no
# painel, e a bolinha de não lida ficava parada com a conversa já respondida.
#
# O que conta (conta?): mensagem que sai (outgoing), pública, mandada por uma pessoa da conta pelo painel ou pela API
# com token de pessoa: remetente User que é membro humano da conta (account_users.integration = false, AccountUser.human)
# e sem `external_echo`. O modelo do WhatsApp (template da Meta) mandado por uma pessoa CONTA: ela leu a conversa para
# responder, e no WhatsApp mandar qualquer coisa numa conversa a deixa lida. Campanha (marca campaign_id ou
# whatsapp_api_campaign_id) e mensagem `message_type: :template` (a automática da caixa: saudação, fora do horário,
# pesquisa) NÃO contam.
# O que não conta (decisões do Rodrigo, #2202):
# - robô (AgentBot, Captain::Assistant), toda saída sem pessoa e o usuário de integração (token do MCP ou do CRM entra
#   como um User sintético da conta, com account_users.integration = true, Mcp::IntegrationToken#create_managed_user):
#   a bolinha fica para a equipe ver o que só o robô ou a integração respondeu;
# - o eco do celular (`external_echo`), com ou sem remetente (no WAHA comum o remetente do eco é o dono do token do
#   conector). Nenhum canal informa se o eco foi uma pessoa digitando, a resposta automática do app Business (ausência,
#   saudação) ou um robô mandando direto pela WAHA: a Cloud (smb_message_echoes) não tem campo de origem, e o `source`
#   da WAHA ("app"/"api") não separa a pessoa da resposta automática do celular. A Issue do sinal de leitura no celular
#   (a pessoa abriu a conversa no aparelho) vai cuidar do eco;
# - nota privada (o cliente não vê);
# - a mensagem que já NASCE com falha (status failed na criação). A falha do envio em si só chega depois, no
#   SendReplyJob, e não desfaz o "visto": a pessoa leu a conversa para responder. O backfill do passado
#   (docs/2202-lista-conversas/backfill-bolinha.sql) exclui toda falhada, porque lá a falha já é sabida;
# - o que uma pessoa manda sem estar respondendo nesta conversa, na lista única de Messages::NaoEResposta (envio
#   automático em nome dela, campanha, cópia encaminhada, modelo reenviado). A importação do histórico não chega aqui
#   (Message#execute_after_create_commit_callbacks sai antes).
#
# Até onde fica vista (antes_do_envio): até o começo do segundo em que a resposta foi criada, menos 1 µs. A tela
# compara em segundos inteiros (getters.js getUnreadCount e conversationHelper.js getUnreadMessages,
# `created_at * 1000 > agent_last_seen_at * 1000`, com os dois em .to_i). Gravando o visto no meio do segundo, a
# mensagem do cliente no mesmo segundo da resposta seria não lida no servidor (bolinha) e lida na tela (divisor).
# Começando no segundo, os dois concordam. EFEITO DO CORTE: a mensagem do cliente que chegou no MESMO segundo da
# resposta, antes ou depois dela, continua não lida (bolinha e divisor). Não há como saber a ordem dentro do segundo
# na tela; errar para "não lida" é o lado seguro. Fora desse segundo, nada muda.
# O "visto" nunca anda para trás: uma leitura mais nova no painel fica.
#
# Roda antes do `dispatch_create_events` original, para o message.created da resposta já levar a não lida zerada.
# Só avisa a tela e os contadores quando havia não lida: resposta em sequência não refaz a contagem.
module ConversaCanal::VistaAoResponder
  UM_MICROSSEGUNDO = Rational(1, 1_000_000)
  LINHAS_DO_BACKTRACE = 5

  def self.conta?(message)
    message.outgoing? && !message.private? && !message.failed? &&
      !::Messages::NaoEResposta.nao_e_resposta?(message) && de_pessoa?(message)
  end

  def self.de_pessoa?(message)
    message.sender_type == 'User' && !eco?(message) &&
      ::AccountUser.human.exists?(account_id: message.account_id, user_id: message.sender_id)
  end

  def self.eco?(message)
    message.content_attributes.to_h.with_indifferent_access['external_echo'].present?
  end

  # -> true quando o "visto" andou.
  def self.marcar!(message)
    conversation = message.conversation
    visto = antes_do_envio(message)
    havia_nao_lida = nao_lida_ate?(conversation, visto)
    return false unless gravar(conversation, visto)

    marcar_avisos_de_quem_respondeu(message, conversation)
    avisar(conversation) if havia_nao_lida
    true
  end

  def self.antes_do_envio(message)
    message.created_at.change(usec: 0) - UM_MICROSSEGUNDO
  end

  # Uma gravação só, condicionada a andar para a frente (a leitura do painel no meio não volta).
  def self.gravar(conversation, visto)
    agora = Time.current
    # rubocop:disable Rails/SkipsModelValidations
    andou = Conversation.where(id: conversation.id).where(visto_antes_de(visto))
                        .update_all(agent_last_seen_at: visto, updated_at: agora).positive?
    # rubocop:enable Rails/SkipsModelValidations
    return false unless andou

    conversation.agent_last_seen_at = visto
    conversation.updated_at = agora
    conversation.clear_attribute_changes(%w[agent_last_seen_at updated_at])
    true
  end

  def self.visto_antes_de(visto)
    coluna = Conversation.arel_table[:agent_last_seen_at]
    coluna.eq(nil).or(coluna.lt(visto))
  end

  # Alguma mensagem do cliente entre o "visto" atual e o novo.
  def self.nao_lida_ate?(conversation, visto)
    recebidas = conversation.messages.where(account_id: conversation.account_id).incoming
                            .where(Message.arel_table[:created_at].lteq(visto))
    recebidas = recebidas.created_since(conversation.agent_last_seen_at) if conversation.agent_last_seen_at.present?
    recebidas.exists?
  end

  # Os avisos do sino desta conversa, só para a pessoa que respondeu (o remetente, que conta? garante ser User) e só
  # quando o "visto" andou.
  def self.marcar_avisos_de_quem_respondeu(message, conversation)
    ::Notification::MarkConversationReadService.new(user: message.sender, account: message.account, conversation: conversation).perform
  end

  # Os mesmos avisos do "lido" ao abrir (ConversaCanal::LidoDaConversa) e o evento para a lista apagar a bolinha.
  # Por que `conversation.read`: é também o evento de "o contato leu" (Conversation#notify_status_change, quando muda
  # contact_last_seen_at). Só o ActionCableListener o ouve (nada de webhook, automação ou CRM, como no
  # conversation.updated), vai só para a equipe da caixa, o ActionCableBroadcastJob relê a conversa do banco, e a tela o
  # trata como atualização da conversa (actionCable.js onConversationRead -> updateConversation), o que traz o
  # unread_count novo para o item da lista. O `conversation.unread_count_changed` não serve para isso: vai vazio ({}) e
  # a tela só recarrega os números da barra lateral; ele já sai pelo Notifier abaixo.
  def self.avisar(conversation)
    ::Conversations::UnreadCounts::Notifier.new(conversation).perform
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(conversation.account).conversation_changed!
    Rails.configuration.dispatcher.dispatch(Events::Types::CONVERSATION_READ, Time.zone.now, conversation: conversation)
  end

  # No teste o erro sobe, para o spec não passar com a marcação quebrada.
  def self.relancar?
    Rails.env.test?
  end

  # O erro original vai para os dois canais, cada um por conta própria: se o log quebra, o rastreador ainda recebe; se o
  # rastreador quebra, o log já recebeu. Só o erro DO PRÓPRIO REGISTRO é descartado aqui, para nunca subir e impedir o
  # send_reply que vem depois.
  def self.registrar_falha(message, error)
    registros = [-> { Rails.logger.error(linha_do_log(message, error)) },
                 -> { ChatwootExceptionTracker.new(error, account: message.account).capture_exception }]
    registros.each do |registro|
      registro.call
    rescue StandardError
      next
    end
  end

  def self.linha_do_log(message, error)
    detalhe = ::CampaignImports::SafeLogMessage.call(error.message)
    rastro = Array(error.backtrace).first(LINHAS_DO_BACKTRACE).join(' | ')
    "[conversa][vista_ao_responder] conversa=#{message.conversation_id} mensagem=#{message.id} #{error.class}: #{detalhe} | #{rastro}"
  end

  private

  def dispatch_create_events
    marcar_conversa_vista
    super
  end

  # A mensagem já está gravada e o envio vem depois: em produção, falhar aqui não pode impedir o envio nem devolver
  # erro a quem postou (o n8n reenviaria e o cliente receberia duas vezes). A falha vai para o log e o rastreador; a
  # próxima resposta marca de novo.
  def marcar_conversa_vista
    return unless ConversaCanal::VistaAoResponder.conta?(self)

    ConversaCanal::VistaAoResponder.marcar!(self)
  rescue StandardError => e
    raise if ConversaCanal::VistaAoResponder.relancar?

    ConversaCanal::VistaAoResponder.registrar_falha(self, e)
  end
end
