class Agents::DestroyJob < ApplicationJob
  queue_as :low

  def perform(account, user)
    ActiveRecord::Base.transaction do
      destroy_notification_setting(account, user)
      remove_user_from_teams(account, user)
      remove_user_from_inboxes(account, user)
      unassign_conversations(account, user)
      release_crm_cards(account, user) if account.feature_enabled?(::Crm::Cards::Restorer::FLAG)
    end
  end

  private

  def remove_user_from_inboxes(account, user)
    inboxes = account.inboxes.all
    inbox_members = user.inbox_members.where(inbox_id: inboxes.pluck(:id))
    inbox_members.destroy_all
  end

  def remove_user_from_teams(account, user)
    teams = account.teams.all
    team_members = user.team_members.where(team_id: teams.pluck(:id))
    team_members.destroy_all
  end

  def destroy_notification_setting(account, user)
    setting = user.notification_settings.find_by(account_id: account.id)
    setting&.destroy!
  end

  def unassign_conversations(account, user)
    # rubocop:disable Rails/SkipsModelValidations
    unassigned_count = user.assigned_conversations.where(account: account).in_batches.update_all(assignee_id: nil)
    # rubocop:enable Rails/SkipsModelValidations

    return unless unassigned_count.positive?

    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).conversation_changed!
  end

  # Os cards da conta ficam sem dono (#2095), como as conversas acima. Com o id de quem saiu, o card não se grava mais
  # (Crm::Card#validate_owner_account): restaurar, mover ou editar dava erro. update_all de propósito: a validação
  # recusaria gravar o próprio card que se quer soltar. Quem vê o card pelo dono ("Só as suas") muda, então os
  # contadores e a visibilidade das conversas dele são refeitos.
  # Só com a flag crm_arquivados ligada na conta (decisão do Rodrigo, 23/10): desligada, o job fica como na main e o
  # card mantém o id de quem saiu.
  def release_crm_cards(account, user)
    cards = account.crm_cards.where(owner_id: user.id)
    conversation_ids = cards.where.not(conversation_id: nil).pluck(:conversation_id) +
                       Crm::CardConversation.where(card_id: cards.select(:id)).pluck(:conversation_id)
    # rubocop:disable Rails/SkipsModelValidations
    released = cards.in_batches.update_all(owner_id: nil, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    return unless released.positive?

    Crm::Access::CountInvalidation.card_changed!(account.id, conversation_ids)
  end
end
