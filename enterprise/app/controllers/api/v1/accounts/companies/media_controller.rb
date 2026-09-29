class Api::V1::Accounts::Companies::MediaController < Api::V1::Accounts::Companies::BaseController
  before_action :ensure_media_enabled!
  before_action :authorize_company_read!
  before_action :private_response!
  rescue_from Relationships::Configuration::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    query = Relationships::CompanyMediaQuery.new(@company, Current.user, request.query_parameters)
    render json: { payload: query.results.map do |attachment|
      serialize(attachment)
    end, meta: { total: query.scope.count, page: query.page, per_page: query.per_page } }
  end

  def contacts
    query = params.fetch(:q, '')
    raise Relationships::Configuration::Invalid, 'Invalid contact query' unless query.is_a?(String) && query.length <= 200

    permitted_contacts = Relationships::CompanyMediaQuery.new(@company, Current.user, {}).authorized_messages
                                                         .joins(:conversation).select('conversations.contact_id')
    contacts = @company.contacts.where(id: permitted_contacts)
    contacts = contacts.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    render json: contacts.order(:name, :id).limit(50).pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  def show
    attachment = authorized_attachment
    ActiveStorage::Current.url_options = request.base_url.then { |url| { host: url } }
    inline = params[:inline] == 'true' && (Relationships::PreviewRenderer::IMAGE_TYPES.include?(attachment.file.content_type) ||
             attachment.file.content_type.in?(%w[application/pdf video/mp4 audio/mpeg audio/ogg]))
    render json: { url: attachment.file.blob.url(expires_in: 1.minute, disposition: inline ? 'inline' : 'attachment') }
  end

  def preview
    attachment = authorized_attachment
    if Relationships::CompanyPreviewJob.ready?(attachment)
      send_data attachment.relationship_preview.download, type: 'image/jpeg', disposition: 'inline'
    else
      status = Relationships::CompanyPreviewJob.request(attachment)
      render json: { status: status }, status: status == 'pending' ? :accepted : :ok
    end
  end

  private

  def ensure_media_enabled!
    head :forbidden unless Current.account_user && Current.account.feature_enabled?('relationships_company_media')
  end

  def private_response!
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def authorized_attachment
    attachment = Relationships::CompanyMediaQuery.new(@company, Current.user, {}).scope.find(params[:id])
    authorize attachment.message.conversation, :show?
    attachment
  end

  def serialize(attachment)
    message = attachment.message
    contact = message.conversation.contact
    { id: attachment.id, filename: attachment.file.filename.to_s, content_type: attachment.file.content_type,
      file_type: attachment.file_type, byte_size: attachment.file.byte_size, created_at: attachment.created_at,
      contact: { id: contact.id, name: contact.name }, sender: message.sender && { type: message.sender_type, name: message.sender.name },
      conversation_id: message.conversation.display_id, message_id: message.id }
  end
end
