class Api::V1::Accounts::Companies::ConversationsController < Api::V1::Accounts::Companies::BaseController
  before_action :authorize_company_read!

  def index
    # Fork (upgrade 4.19.1): the 20 most recent, without pages, as the CRM screens expect.
    @conversations = company_conversations.includes(:assignee, :contact, :inbox, :taggings)
                                          .preload(ai_assignee: { avatar_attachment: [:blob] })
                                          .order(last_activity_at: :desc).limit(20)
  end

  def filter
    @conversations = Companies::ConversationFilterService.new(
      params.permit!, Current.user, Current.account, company: @company
    ).perform[:conversations]
    render :index
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  private

  def company_conversations
    @company_conversations ||= Conversations::PermissionFilterService.new(
      Current.account.conversations.where(contact_id: @company.contacts.select(:id)),
      Current.user,
      Current.account
    ).perform
  end
end
