module Enterprise::Api::V1::Accounts::ConversationsController
  extend ActiveSupport::Concern

  def inbox_assistant
    assistant = @conversation.inbox.captain_assistant

    if assistant
      render json: { assistant: { id: assistant.id, name: assistant.name } }
    else
      render json: { assistant: nil }
    end
  end

  def reporting_events
    @reporting_events = @conversation.reporting_events.order(created_at: :asc)
  end

  def permitted_update_params
    # SLA is a premium feature; only accept sla_policy_id assignment when it is enabled for the account
    # (gate consistente com controllers/jobs/callback de SLA: nem a coluna FK inerte pode ser setada).
    return super unless Current.account.feature_enabled?('sla')

    super.merge(params.permit(:sla_policy_id))
  end

  private

  # Quem só lê (conversation_view sem o trio) não começa conversa (#1800). Antes do contact_inbox, que já grava o
  # vínculo contato↔caixa.
  def contact_inbox
    authorize Conversation, :create?
    super
  end

  def copilot_params
    params.permit(:previous_history, :message, :assistant_id)
  end
end
