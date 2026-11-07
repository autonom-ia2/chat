# Cliente com card aberto que escreve por outro canal (#1150, R13; decisão do Rodrigo em 12/10): a conversa nova é
# ligada ao card aberto mais recente dele e vai para o dono do card, sem passar pela triagem.
#
# Só conversa que o cliente abriu (primeira mensagem dele), aberta, recente (até JANELA), sem card, numa caixa do CRM;
# card aberto de OUTRA caixa (na mesma caixa vale a deduplicação de sempre, AutoCreateDeduplicator) com atividade na
# janela dela. A entrega ao dono só acontece se
# ninguém começou a atender: sem resposta de pessoa e sem agente de IA na conversa (com IA, ela segue e a passagem
# para humano usa o rodízio do funil, R12). Dono que não está na caixa ou não tem o funil ali: só liga ao card.
class Crm::Conversations::OpenCardRouter
  JANELA = 1.hour

  def initialize(conversation:)
    @conversation = conversation
    @account = conversation.account
  end

  def perform
    return unless elegivel?

    card = card_aberto
    return if card.nil?

    Crm::Cards::ConversationLinker.new(card: card, conversation: @conversation, actor: nil).link
    entregar_ao_dono(card)
    card
  rescue ActiveRecord::RecordInvalid => e
    # O card tem conversa de outro contato vinculada: não liga, e a sincronização segue como antes.
    Rails.logger.warn("[crm.open_card_router] conversa #{@conversation.id} não ligada ao card: #{e.message}")
    nil
  end

  private

  # Do mais barato ao mais caro: a maioria das mensagens sai na primeira linha.
  def elegivel?
    @conversation.open? && @conversation.contact_id.present? && @conversation.created_at >= JANELA.ago &&
      aberta_pelo_cliente? && caixa_no_crm? &&
      Crm::Cards::ConversationCardFinder.new(account: @account).all(@conversation).none?
  end

  def aberta_pelo_cliente?
    primeira = @conversation.messages.where(message_type: %i[incoming outgoing template]).reorder(:id).first
    primeira.present? && primeira.incoming?
  end

  # Mesmo critério do CardSyncer: caixa sem configuração conta como do CRM se tem funil ligado a ela.
  def caixa_no_crm?
    setting = @account.crm_inbox_settings.find_by(inbox_id: @conversation.inbox_id)
    return setting.crm_enabled? if setting

    @account.crm_pipeline_inboxes.exists?(inbox_id: @conversation.inbox_id)
  end

  def card_aberto
    @account.crm_cards.where(contact_id: @conversation.contact_id, status: :open)
            .where('crm_cards.inbox_id IS DISTINCT FROM ?', @conversation.inbox_id)
            .where('COALESCE(crm_cards.last_activity_at, crm_cards.updated_at) >= ?', janela_do_card.ago)
            .order(Arel.sql('COALESCE(crm_cards.last_activity_at, crm_cards.updated_at) DESC, crm_cards.id DESC')).first
  end

  def janela_do_card
    dedup = Crm::Conversations::AutoCreateDeduplicator
    days = Integer(ENV.fetch(dedup::DEDUP_WINDOW_ENV, dedup::DEFAULT_DEDUP_WINDOW_DAYS), exception: false)
    (days.presence || dedup::DEFAULT_DEDUP_WINDOW_DAYS).days
  end

  # Com trava e relendo a conversa: se uma pessoa ou a IA começou a atender nesse meio tempo, a conversa fica com ela.
  def entregar_ao_dono(card)
    dono = card.owner
    return unless dono_pode_receber?(dono, card)

    @conversation.with_lock do
      next unless ninguem_atendendo?
      next if @conversation.assignee_id == dono.id

      @conversation.update!(assignee: dono)
    end
  end

  def dono_pode_receber?(dono, card)
    dono.present? && @conversation.inbox.members.exists?(id: dono.id) &&
      Crm::Access::CardScope.new(user: dono, account: @account).pipeline_allowed?(@conversation.inbox_id, card.pipeline_id)
  end

  def ninguem_atendendo?
    @conversation.assignee_agent_bot_id.blank? && !@conversation.messages.outgoing.exists?(sender_type: 'User')
  end
end
