# #1462 — "quem recebe" vindo do painel. Sem o campo, fica o de antes (legacy), para automações e chamadas antigas.
# Pessoas escolhidas precisam, com card, passar na mesma regra do "Quem cuida" (Crm::Access::OwnerOptions, que a
# tela usa para desligar quem não pode); "quem cuida do cliente" só existe com card. No aviso, quem não vê o card ainda
# é filtrado (RecipientResolver).
class Crm::FollowUps::RecipientParams
  class Invalid < StandardError; end

  MODES = Crm::FollowUpRecipients::RECIPIENT_MODES.keys.map(&:to_s).freeze

  def initialize(account:, card:, attributes:, user: nil, account_user: nil)
    @account = account
    @card = card
    @user = user
    @account_user = account_user
    @attributes = attributes.to_h.with_indifferent_access
  end

  def perform
    mode = @attributes[:recipient_mode].presence
    return {} if mode.nil?
    raise Invalid, 'crm.follow_up.recipient_mode_invalid' unless MODES.include?(mode)
    raise Invalid, 'crm.follow_up.recipient_owner_needs_card' if mode == 'card_owner' && @card.nil?

    { recipient_mode: mode, recipient_user_ids: user_ids(mode), recipient_team_id: team_id(mode) }
  end

  private

  def user_ids(mode)
    return [] unless mode == 'users'

    ids = Array(@attributes[:recipient_user_ids]).compact_blank.map(&:to_i).uniq
    blocked = @card ? blocked_ids : []
    raise Invalid, 'crm.follow_up.recipient_without_funnel' if ids.intersect?(blocked)

    ids
  end

  def blocked_ids
    account_user = @account_user || AccountUser.find_by(account_id: @account.id, user_id: @user&.id)
    options = Crm::Access::OwnerOptions.new(user: @user, account: @account, account_user: account_user)
    options.blocked(@card.inbox_id, @card.pipeline_id) | Crm::Access::Recipients.card_blocked_user_ids(@card)
  end

  def team_id(mode)
    return nil unless mode == 'team'

    @account.teams.find(@attributes[:recipient_team_id]).id
  rescue ActiveRecord::RecordNotFound
    raise Invalid, 'crm.follow_up.recipient_team_invalid'
  end
end
