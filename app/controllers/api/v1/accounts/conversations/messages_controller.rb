class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update
  before_action :link_waha_source_ids, only: :update

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    ::SendReplyJob.perform_later(message.id) if claim_message_retry
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  rescue Google::Cloud::Error => e
    # `details` carries the clean human message; `message` includes gRPC debug noise
    render_could_not_create_error(e.details.presence || e.message)
  end

  private

  def link_waha_source_ids
    return unless waha_source_ids_request?

    return head :forbidden unless waha_connector_token?

    ids = params[:waha_source_ids]
    return render_could_not_create_error('Invalid WAHA message source IDs') unless valid_waha_source_ids?(ids)
    return render_could_not_create_error('WAHA source IDs require a public outgoing message') unless message.outgoing? && !message.private?

    Waha::MessageSourceIds.new(message: message, source_ids: ids).perform
  rescue Waha::MessageSourceIds::IdentityConflict
    render_could_not_create_error('WAHA message identity changed; no source IDs were overwritten')
  end

  def waha_source_ids_request?
    channel = @conversation.inbox.channel
    params.key?(:waha_source_ids) && channel.waha_provider? && channel.additional_attributes['waha_history_import'].present?
  end

  def waha_connector_token?
    owner_id = @conversation.inbox.channel.additional_attributes.fetch('account_token_owner_user_id')
    authenticate_by_access_token? && Current.user.is_a?(User) && Current.user.id == owner_id
  end

  def valid_waha_source_ids?(ids)
    return false unless ids.is_a?(Array) && ids.present?

    ids.uniq == ids && ids.all? do |id|
      id.is_a?(String) && id.present? && id.length <= ApplicationRecord::MAX_STRING_COLUMN_LENGTH
    end
  end

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def claim_message_retry
    message.with_lock do
      next false unless message.failed?

      Messages::StatusUpdateService.new(message, 'sent').perform
      previous_source_id = message.source_id
      retry_attributes = { content_attributes: retry_content_attributes }
      retry_attributes[:source_id] = nil unless @conversation.inbox.api? || @conversation.inbox.web_widget?
      message.update!(retry_attributes)
      if retry_attributes.key?(:source_id) && previous_source_id.present?
        Rails.logger.info "Cleared older source ID #{previous_source_id} for message #{message.id}"
      end
      true
    end
  end

  def retry_content_attributes
    return message.content_attributes if message.content_attributes.dig('whatsapp_contact_info', 'type') == 'request'

    {}
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end

Api::V1::Accounts::Conversations::MessagesController.prepend_mod_with('Api::V1::Accounts::Conversations::MessagesController')
