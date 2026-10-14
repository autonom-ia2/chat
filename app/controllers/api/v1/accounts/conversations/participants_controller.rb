class Api::V1::Accounts::Conversations::ParticipantsController < Api::V1::Accounts::Conversations::BaseController
  include Events::Types

  before_action :validate_participant_ids, only: [:create, :update]

  def show
    @participants = @conversation.conversation_participants
  end

  def create
    participant_ids_to_add = participants_to_be_added_ids

    ActiveRecord::Base.transaction do
      @participants = participant_ids_to_add.map { |user_id| @conversation.conversation_participants.find_or_create_by!(user_id: user_id) }
    end
    notify_unread_count_change if participant_ids_to_add.any?
  end

  def update
    participant_ids_to_add = participants_to_be_added_ids
    participant_ids_to_remove = participants_to_be_removed_ids
    changed_participant_ids = participant_ids_to_add + participant_ids_to_remove

    ActiveRecord::Base.transaction do
      participant_ids_to_add.each { |user_id| @conversation.conversation_participants.find_or_create_by!(user_id: user_id) }
      participant_ids_to_remove.each { |user_id| @conversation.conversation_participants.find_by(user_id: user_id)&.destroy }
    end
    notify_unread_count_change if changed_participant_ids.any?
    @participants = @conversation.conversation_participants.reload
    render action: 'show'
  end

  def destroy
    participant_ids_to_remove = current_participant_ids & params[:user_ids]

    ActiveRecord::Base.transaction do
      params[:user_ids].map { |user_id| @conversation.conversation_participants.find_by(user_id: user_id)&.destroy }
    end
    notify_unread_count_change if participant_ids_to_remove.any?
    head :ok
  end

  private

  def participants_to_be_added_ids
    participant_ids - current_participant_ids
  end

  def participants_to_be_removed_ids
    current_participant_ids - participant_ids
  end

  def current_participant_ids
    @current_participant_ids ||= @conversation.conversation_participants.pluck(:user_id)
  end

  def participant_ids
    @participant_ids ||= params[:user_ids].map(&:to_i)
  end

  def validate_participant_ids
    return render json: { error: 'Restricted agents cannot add themselves' }, status: :forbidden if self_add_blocked?

    invalid_ids = participants_to_be_added_ids - @conversation.inbox.assignable_agents.map(&:id)
    return if invalid_ids.empty?

    render json: { error: 'Invalid participant IDs' }, status: :unprocessable_entity
  end

  # Acesso por funil (#1148): participante sempre vê. Quem tem acesso restrito na caixa não se dá esse passe; ser
  # adicionado por outra pessoa continua valendo (decisão do Rodrigo, 11/10).
  def self_add_blocked?
    participants_to_be_added_ids.include?(Current.user.id) &&
      Crm::Access::ConversationScope.new(user: Current.user, account: Current.account).restricted_in?(@conversation.inbox_id)
  end

  def notify_unread_count_change
    return unless Current.account.feature_enabled?('conversation_unread_counts')
    return unless Current.account.feature_enabled?('unread_count_for_filters')

    Rails.configuration.dispatcher.dispatch(CONVERSATION_UNREAD_COUNT_CHANGED, Time.zone.now, conversation: @conversation)
  end
end
