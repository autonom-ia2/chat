# Meta callbacks required by Instagram Business Login before App Review:
# - deauthorize: the account owner removed the app → flag the inbox for reconnection, keep everything.
# - data_deletion: the owner asked Meta to delete their data → drop the stored token (the only data we hold
#   from Instagram itself) and flag the inbox. Conversations stay with the business that owns the inbox.
class Instagram::DataDeletionsController < ActionController::API
  include InstagramConcern

  STATUS_PURPOSE = :instagram_data_deletion

  before_action :verify_signed_request!, only: [:deauthorize, :create]

  def deauthorize
    each_channel(&:prompt_reauthorization!)
    head :ok
  end

  def create
    each_channel(&:revoke_access!)
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

  # Meta sends the app-scoped id (/me `id`); instagram_id (/me `user_id`) covers channels connected before
  # app_scoped_user_id existed and not yet reconnected. The same Instagram can be an inbox in more than one account
  # (#2781): the request is about the person, so it reaches every channel.
  def instagram_channels
    user_id = @signed_payload['user_id'].to_s
    return [] if user_id.blank?

    channels = Channel::Instagram.where(app_scoped_user_id: user_id).or(Channel::Instagram.where(instagram_id: user_id)).order(:id).to_a
    Rails.logger.warn("Instagram #{action_name} callback: no channel for user_id #{user_id}") if channels.empty?
    channels
  end

  # Uma caixa que falha não impede as outras: o erro fica no log e no rastreador, e a Meta recebe a resposta.
  def each_channel
    instagram_channels.each do |channel|
      yield channel
    rescue StandardError => e
      Rails.logger.warn("Instagram #{action_name} callback: channel #{channel.id} failed with #{e.class}")
      ChatwootExceptionTracker.new(e, account: channel.account).capture_exception
    end
  end

  def status_verifier
    Rails.application.message_verifier(STATUS_PURPOSE)
  end
end
