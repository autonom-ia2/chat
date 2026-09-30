class Api::V1::Accounts::Companies::MediaController < Api::V1::Accounts::Companies::BaseController
  include Relationships::MediaActions

  before_action :ensure_media_enabled!
  before_action :authorize_company_read!
  before_action :private_response!
  rescue_from Relationships::Configuration::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
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

  private

  def relationship_record
    @company
  end

  def ensure_media_enabled!
    head :forbidden unless Current.account_user && Current.account.feature_enabled?('relationships_company_media')
  end
end
