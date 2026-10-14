# #1462 — "quem recebe" vindo do painel. Sem o campo, fica o de antes (legacy), para automações e chamadas antigas.
# Pessoas escolhidas precisam estar na conta e, com card, ver o funil dele (a mesma regra do "Quem cuida",
# owner_options / CardGuard); "quem cuida do cliente" só existe com card.
class Crm::FollowUps::RecipientParams
  class Invalid < StandardError; end

  MODES = Crm::FollowUpRecipients::RECIPIENT_MODES.keys.map(&:to_s).freeze

  def initialize(account:, card:, attributes:)
    @account = account
    @card = card
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
    blocked = @card ? Crm::Access::Recipients.card_blocked_user_ids(@card) : []
    raise Invalid, 'crm.follow_up.recipient_without_funnel' if ids.intersect?(blocked)

    ids
  end

  def team_id(mode)
    return nil unless mode == 'team'

    @account.teams.find(@attributes[:recipient_team_id]).id
  rescue ActiveRecord::RecordNotFound
    raise Invalid, 'crm.follow_up.recipient_team_invalid'
  end
end
