# REABERTURA COM O DONO AUSENTE (#1140, decisão 5 do Rodrigo em 16/10/2026). O cliente volta a uma conversa resolvida e
# ela reabre no nome de quem estava com ela. Antes, ficava com essa pessoa mesmo offline ou de férias: a IA não falava
# (tem pessoa no nome) e ninguém procurava outra pessoa.
#
# A regra é a do outro canal (R13 do #1150, Crm::Entrega::Dono), com quem estava no nome como dono:
# - dono online: fica com a conversa, nada muda;
# - dono offline e o funil do assunto com regra de Atribuição: vale a regra (rodízio, pessoa fixa, convite, segurar),
#   inclusive passando ao agente de IA;
# - dono offline e sem regra (sem card, ou o funil sem regra): a conversa espera por ele (a marca do motor guarda o
#   dono, e a fila entrega quando ele entrar). Com robô na caixa, o robô fica no nome e atende enquanto isso, como em
#   toda passagem que espera pessoa (ConversationBotHandoff);
# - dono fora da fila de quem cuida (saiu da caixa, "Só as que atende", sem o funil): vale a fila de sempre, como no
#   outro canal.
# Presença fora do ar: não se sabe se o dono está online, então nada muda.
#
# Ex.: o João volta à conversa resolvida pela Ana, que está de férias. Com regra no funil, o Bruno (online) recebe; sem
# regra, a conversa espera a Ana e o robô da caixa responde o João até ela voltar.
#
# Mesma flag do outro canal (`crm_outro_canal`): é o mesmo conceito de dono e o mesmo piloto (contas 1, 16 e 18).
# Chamado por Message#reopen_conversation, depois que a mensagem do cliente reabriu a conversa (fora de transação).
class Crm::Entrega::Reabertura
  MOTIVO = 'reabertura'.freeze

  def initialize(conversation:)
    @conversation = conversation
  end

  # Uma falha aqui não pode derrubar a mensagem do cliente (já gravada): a conversa fica reaberta com o dono, como
  # antes, e o erro vai para o rastreador.
  def call
    return unless @conversation.account.feature_enabled?(Crm::Conversations::OutroCanal::FLAG)

    dono = @conversation.assignee
    return if dono.nil? || online?(dono)

    @conversation.with_lock { passar(dono) }
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.error("[crm][reabertura] conversa=#{@conversation.id} erro=#{e.class}")
  end

  private

  # Sob a trava, relendo (o with_lock recarrega): se outra pessoa assumiu nesse meio tempo, fica com ela.
  def passar(dono)
    return unless @conversation.assignee_id == dono.id

    @conversation.bot_handoff!(dispatch_event: false, motivo: MOTIVO, release_assignee: true, dono: dono)
    registrar(dono)
  end

  # A presença é lida antes da trava (o Redis fora da transação).
  def online?(dono)
    Crm::Entrega::Presenca.online_ids!(@conversation.account_id).include?(dono.id)
  rescue Crm::Ai::HandoffMemberSelector::PresencaIndisponivel
    Rails.logger.warn("[crm][reabertura] conversa=#{@conversation.id} presenca_indisponivel: fica com o dono")
    true
  end

  # Só ids (nunca texto do cliente).
  def registrar(dono)
    Rails.logger.info(
      "[crm][reabertura] conversa=#{@conversation.id} conta=#{@conversation.account_id} dono=#{dono.id} " \
      "agora=#{@conversation.assignee_id || '-'}"
    )
  end
end
