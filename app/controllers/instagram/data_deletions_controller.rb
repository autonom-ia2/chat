# Meta callbacks required by Instagram Business Login before App Review:
# - deauthorize: the account owner removed the app → flag the inbox for reconnection, keep everything.
# - data_deletion: the owner asked Meta to delete their data → drop the stored token (the only data we hold
#   from Instagram itself) and flag the inbox. Conversations stay with the business that owns the inbox.
class Instagram::DataDeletionsController < ActionController::API
  include InstagramConcern

  STATUS_PURPOSE = :instagram_data_deletion

  before_action :verify_signed_request!, only: [:deauthorize, :create]

  def deauthorize
    instagram_channel&.prompt_reauthorization!
    head :ok
  end

  def create
    instagram_channel&.revoke_access!
    code = status_verifier.generate({ 'processed_at' => Time.current.iso8601 })

    render json: { url: "#{base_url}/instagram/data_deletion_status?code=#{CGI.escape(code)}", confirmation_code: code }
  end

  def status
    data = status_verifier.verified(params[:code].to_s)
    return head :not_found if data.blank?

    render json: { status: 'completed', processed_at: data['processed_at'] }
  end

  private

  def verify_signed_request!
    @signed_payload = Instagram::SignedRequest.parse(params[:signed_request], client_secret)
    head :unauthorized if @signed_payload.blank?
  end

  def instagram_channel
    user_id = @signed_payload['user_id'].to_s
    return if user_id.blank?

    channel = Channel::Instagram.find_by(instagram_id: user_id)
    # Meta documents this id as app-scoped; log misses so a mismatch with the stored account id is visible.
    Rails.logger.warn("Instagram #{action_name} callback: no channel for user_id #{user_id}") if channel.nil?
    channel
  end

  def status_verifier
    Rails.application.message_verifier(STATUS_PURPOSE)
  end
end
