class Api::V1::Accounts::Companies::ContactsController < Api::V1::Accounts::Companies::BaseController
  RESULTS_PER_PAGE = 15
  CONTACT_SEARCH_QUERY = [
    'contacts.name ILIKE :search',
    'contacts.email ILIKE :search',
    'contacts.phone_number ILIKE :search',
    'contacts.identifier ILIKE :search'
  ].join(' OR ')

  before_action :authorize_company_read!, only: [:index, :search]
  before_action :authorize_company_update!, only: [:create, :destroy]
  before_action :set_current_page, only: [:index, :search]
  before_action :fetch_contact, only: [:destroy]

  def index
    @contacts = fetch_contacts(@company.contacts.order(:name, :id))
    @contacts_count = @contacts.total_count
  end

  def search
    if termo_da_busca.blank?
      return render json: { error: 'Specify search string with parameter q' },
                    status: :unprocessable_entity
    end

    @contacts = fetch_contacts(contact_search_scope)
    @contacts_count = @contacts.total_count
  end

  def create
    @contact = Current.account.contacts.find(params[:contact_id])
    membership_service.assign(contact: @contact)
  end

  def destroy
    membership_service.remove(contact: @contact)
    head :ok
  end

  private

  def set_current_page
    @current_page = params[:page] || 1
  end

  def fetch_contact
    @contact = @company.contacts.find(params[:id])
  end

  def fetch_contacts(contacts)
    contacts
      .includes({ avatar_attachment: [:blob] }, :company)
      .page(@current_page)
      .per(RESULTS_PER_PAGE)
  end

  def contact_search_scope
    Current.account.contacts
           .where('contacts.company_id IS NULL OR contacts.company_id != ?', @company.id)
           .where(CONTACT_SEARCH_QUERY, search: "%#{ActiveRecord::Base.sanitize_sql_like(termo_da_busca)}%")
           .order(:name, :id)
  end

  # #3078 — `q` só vale como texto (q[]=… ou q[a]=… não chega ao LIKE), e % e _ escritos são letras, não curingas.
  def termo_da_busca
    @termo_da_busca ||= params[:q].is_a?(String) ? params[:q].strip : ''
  end

  def membership_service
    @membership_service ||= Companies::ContactMembershipService.new(company: @company)
  end
end
