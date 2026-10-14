# #1462 — quem recebe o aviso de um lembrete (crm_follow_ups e crm_follow_up_series).
# - legacy: o de antes do #1462 — quem vê o card e o responsável. Toda linha antiga e toda automação continuam assim.
# - card_owner: quem cuida do cliente NO MOMENTO do aviso (troca de dono leva o aviso junto).
# - creator: só quem marcou.
# - users: as pessoas escolhidas (recipient_user_ids).
# - team: quem estiver no time (recipient_team) no momento do aviso.
module Crm::FollowUpRecipients
  extend ActiveSupport::Concern

  RECIPIENT_MODES = { legacy: 0, card_owner: 1, creator: 2, users: 3, team: 4 }.freeze

  included do
    belongs_to :recipient_team, class_name: 'Team', optional: true

    enum :recipient_mode, RECIPIENT_MODES, prefix: :recipients

    validate :recipients_must_be_coherent
  end

  private

  def recipients_must_be_coherent
    validate_recipient_users if recipients_users?
    validate_recipient_team if recipients_team?
  end

  def validate_recipient_users
    ids = Array(recipient_user_ids).compact.uniq
    return errors.add(:recipient_user_ids, :blank) if ids.empty?
    return if account_id.blank?
    return if AccountUser.where(account_id: account_id, user_id: ids).distinct.count(:user_id) == ids.size

    errors.add(:recipient_user_ids, 'must belong to the same account')
  end

  def validate_recipient_team
    return errors.add(:recipient_team, :blank) if recipient_team.blank?
    return if recipient_team.account_id == account_id

    errors.add(:recipient_team, 'must belong to the same account')
  end
end
