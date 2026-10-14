# #1462 — quem recebe o aviso de um lembrete, resolvido NO MOMENTO do aviso (Crm::FollowUpRecipients):
# - legacy: quem vê o card e o responsável (o de antes; automações e linhas antigas);
# - card_owner: quem cuida do cliente agora; sem dono, o responsável ou quem marcou;
# - creator, users, team: quem marcou, as pessoas escolhidas, quem está no time agora.
# Acesso por funil (#1148, parte C): quem não vê o card nunca recebe o título dele. Ninguém sobrando (time vazio,
# pessoas que saíram da conta), o aviso vai para quem marcou, para não se perder em silêncio.
class Crm::FollowUps::RecipientResolver
  def initialize(follow_up)
    @follow_up = follow_up
    @card = follow_up.card
  end

  def users
    found = visible(members(candidates))
    return found if found.any? || @follow_up.recipients_legacy?

    visible(members([@follow_up.created_by]))
  end

  private

  def candidates
    case @follow_up.recipient_mode
    when 'card_owner' then [card_owner]
    when 'creator' then [@follow_up.created_by]
    when 'users' then User.where(id: @follow_up.recipient_user_ids).to_a
    when 'team' then @follow_up.recipient_team&.members.to_a
    else legacy_users
    end
  end

  def card_owner
    @card&.owner || @follow_up.assignee || @follow_up.created_by
  end

  def legacy_users
    users = @card.present? ? Crm::Cards::Broadcaster.recipient_users_for(@card) : [@follow_up.created_by]
    users + [@follow_up.assignee]
  end

  # Só quem ainda está na conta.
  def members(users)
    users = users.compact.uniq(&:id)
    return users if users.empty?

    active_ids = AccountUser.where(account_id: @follow_up.account_id, user_id: users.map(&:id)).pluck(:user_id)
    users.select { |user| active_ids.include?(user.id) }
  end

  def visible(users)
    return users if @card.nil?

    blocked = Crm::Access::Recipients.card_blocked_user_ids(@card)
    users.reject { |user| blocked.include?(user.id) }
  end
end
