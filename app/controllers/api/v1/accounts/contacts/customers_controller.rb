# "Marcar como cliente" do painel do contato (#1144), para quem não fecha a venda pelo ganho do card. Rota própria,
# fora da edição comum: contact_type e customer_since não entram em ContactsController#permitted_params.
class Api::V1::Accounts::Contacts::CustomersController < Api::V1::Accounts::Contacts::BaseController
  before_action :authorize_contact_update

  def create
    @contact.become_customer!
    render :show
  end

  def destroy
    @contact.release_customer!
    render :show
  end

  private

  def authorize_contact_update
    authorize @contact, :update?
  end
end
