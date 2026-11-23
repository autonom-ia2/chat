class Api::V1::Accounts::Companies::NotesController < Api::V1::Accounts::Companies::BaseController
  before_action :authorize_company_read!

  # Fork (upgrade 4.19.1, #3119): the 20 latest notes, without page or search, as before the upstream moved this file.
  def index
    @notes = Current.account.notes
                    .where(contact_id: @company.contacts.select(:id))
                    .latest
                    .includes(:contact, :user)
                    .limit(20)
  end
end
