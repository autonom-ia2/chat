# Saída da triagem e participantes (#1150, R10; decisão do Rodrigo em 12/10). Roda junto com a visão da conversa
# (VisibilitySync), sempre que um card dela nasce ou muda:
# - quem atende tem acesso restrito na caixa, não é "Só as suas" e não tem o funil de nenhum card aberto da conversa:
#   a conversa sai dela (e o card que era dela fica sem dono). O rodízio do funil escolhe quem assume, e o CardSyncer
#   faz dessa pessoa a dona do card. Sem rodízio na caixa, a conversa fica "Não atribuída" para quem tem o funil.
# - o dono de um card aberto que não é quem atende entra como participante: card novo não transfere a conversa. Só
#   quem é membro da caixa e tem o funil do card (participante vê a conversa e entra no rodízio).
# Só em caixa com alguém de acesso restrito: sem acesso por funil, nada acontece. A liberação usa a mesma trava do
# CardSyncer e só grava se o atendente ainda for o mesmo.
class Crm::Access::TriageExit
  def initialize(conversation)
    @conversation = conversation
    @account = conversation.account
  end

  def perform
    return unless Crm::Access::AccountFlag.any?(@account.id)
    return unless Crm::InboxAgentAccess.exists?(account_id: @account.id, inbox_id: @conversation.inbox_id)
    return if open_cards.empty?

    release_triage_assignee if triage_assignee?(@conversation.assignee)
    add_owners_as_participants
  end

  private

  def triage_assignee?(assignee)
    return false if assignee.blank?

    access = Crm::Access::ConversationScope.new(user: assignee, account: @account).access_for(@conversation.inbox_id)
    return false if access.nil? || access.only_own?

    card_scope = Crm::Access::CardScope.new(user: assignee, account: @account)
    open_cards.none? { |card| card_scope.pipeline_allowed?(@conversation.inbox_id, card.pipeline_id) }
  end

  # Sob a trava do CardSyncer (conversa e contato), relendo o atendente: se alguém atribuiu outra pessoa nesse meio
  # tempo, ela fica. Cards e conversa mudam juntos.
  def release_triage_assignee
    previous_id = @conversation.assignee_id
    Crm::Conversations::SyncLock.new(account: @account, conversation: @conversation).perform do
      next unless @conversation.assignee_id == previous_id

      open_cards.each(&:reload).select { |card| card.owner_id == previous_id }.each { |card| card.update!(owner_id: nil) }
      @conversation.update!(assignee_id: nil)
    end
  end

  def add_owners_as_participants
    candidates.each do |owner|
      @conversation.conversation_participants.find_or_create_by!(user_id: owner.id)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Dois eventos do mesmo card ao mesmo tempo: o outro já gravou o participante.
      Rails.logger.warn("[crm.access.triage_exit] participante não gravado na conversa #{@conversation.id}: #{e.class}")
    end
  end

  # Donos de cards abertos que não atendem a conversa, são membros da caixa e têm o funil do próprio card.
  def candidates
    member_ids = @conversation.inbox.members.pluck(:id)
    owners = open_cards.reject { |card| card.owner_id.blank? || card.owner_id == @conversation.assignee_id }
                       .select { |card| member_ids.include?(card.owner_id) && owner_has_funnel?(card) }
    User.where(id: owners.map(&:owner_id).uniq)
  end

  def owner_has_funnel?(card)
    Crm::Access::CardScope.new(user: card.owner, account: @account).pipeline_allowed?(@conversation.inbox_id, card.pipeline_id)
  end

  def open_cards
    @open_cards ||= begin
      linked = Crm::CardConversation.where(account_id: @account.id, conversation_id: @conversation.id).select(:card_id)
      cards = Crm::Card.where(account_id: @account.id, status: Crm::Access::ConversationScope::OPEN)
      cards.where(conversation_id: @conversation.id).or(cards.where(id: linked)).to_a
    end
  end
end
