class Api::V1::Accounts::InboxMembersController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :current_agents_ids, only: [:create, :update]

  def show
    authorize @inbox, :settings?
    fetch_updated_agents
  end

  def create
    authorize @inbox, :create?
    return if invalid_user_ids?

    ActiveRecord::Base.transaction do
      @inbox.add_members(agents_to_be_added_ids)
    end
    fetch_updated_agents
  end

  def update
    authorize @inbox, :update?
    return if invalid_user_ids?

    update_agents_list
    fetch_updated_agents
  end

  def destroy
    authorize @inbox, :destroy?
    ActiveRecord::Base.transaction do
      @inbox.remove_members(params[:user_ids])
    end
    head :ok
  end

  private

  def fetch_updated_agents
    @agents = Current.account.users.where(id: @inbox.members.select(:user_id))
  end

  def update_agents_list
    # get all the user_ids which the inbox currently has as members.
    # get the list of  user_ids from params
    # the missing ones are the agents which are to be deleted from the inbox
    # the new ones are the agents which are to be added to the inbox
    ActiveRecord::Base.transaction do
      @inbox.add_members(agents_to_be_added_ids)
      @inbox.remove_members(agents_to_be_removed_ids)
    end
  end

  def agents_to_be_added_ids
    params[:user_ids] - @current_agents_ids
  end

  def agents_to_be_removed_ids
    @current_agents_ids - params[:user_ids]
  end

  def current_agents_ids
    @current_agents_ids = @inbox.members.pluck(:id)
  end

  # Only people of this account join an inbox (#1931), as in TeamMembersController. Checked after authorize, so only
  # who manages the inbox learns the answer. An id with no user at all keeps failing on the model ("User must exist").
  def invalid_user_ids?
    invalid_ids = User.where(id: Array(params[:user_ids])).pluck(:id) - Current.account.user_ids
    render json: { error: 'Invalid User IDs' }, status: :unauthorized if invalid_ids.present?
    invalid_ids.present?
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end
end
