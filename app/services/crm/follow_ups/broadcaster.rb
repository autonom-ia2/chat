class Crm::FollowUps::Broadcaster
  include Events::Types

  REMINDER_MODES = %w[reminder_only snooze_conversation].freeze
  # O que o cartão do painel lê do `metadata` para reconhecer o alerta do agendamento (`Notices::AgentAlert`, #1291).
  # O poll (`_follow_up.json.jbuilder`) já manda o `metadata`; aqui vai só o que o cartão usa.
  ALERT_METADATA = %w[source event meeting_id kind reason contact_name starts_at].freeze

  def self.broadcast_due(follow_up)
    new(follow_up).perform
  end

  def initialize(follow_up)
    @follow_up = follow_up
  end

  def perform
    return unless ::Crm::Config.enabled?
    return unless REMINDER_MODES.include?(@follow_up.automation_mode)
    return unless @follow_up.overdue?

    recipient_users.each do |user|
      next if user.pubsub_token.blank?
      next if Crm::FollowUps::ReminderDismisser.dismissed_for?(follow_up: @follow_up, user: user)

      ActionCableBroadcastJob.perform_later(
        [user.pubsub_token],
        CRM_FOLLOW_UP_DUE,
        payload_for(user)
      )
    end
  end

  private

  def payload_for(_user)
    card = @follow_up.card
    {
      account_id: @follow_up.account_id,
      id: @follow_up.id,
      title: @follow_up.title,
      description: @follow_up.description,
      automation_mode: @follow_up.automation_mode,
      due_at: @follow_up.due_at&.iso8601,
      card_id: card&.id,
      card: card.present? ? { id: card.id, title: card.title, pipeline_id: card.pipeline_id } : nil,
      assignee_id: @follow_up.assignee_id,
      metadata: @follow_up.metadata.to_h.stringify_keys.slice(*ALERT_METADATA)
    }
  end

  # Quem recebe (#1462) e o acesso por funil (#1148, parte C) moram no RecipientResolver.
  def recipient_users
    Crm::FollowUps::RecipientResolver.new(@follow_up).users
  end
end
