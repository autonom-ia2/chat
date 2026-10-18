class Api::V1::Accounts::Conversations::BaseController < Api::V1::Accounts::BaseController
  before_action :conversation

  private

  # GET só lê (view?, inclui quem tem conversation_view); o resto escreve e segue em show? (#1800).
  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, request.get? ? :view? : :show?
  end
end
