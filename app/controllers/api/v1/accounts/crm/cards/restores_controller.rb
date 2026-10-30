# Restaurar vários cards arquivados (#2095): tudo numa transação (Crm::Cards::BulkRestorer). Cada card passa pela regra
# do card único (Crm::CardPolicy#restore?); o recusado volta em `skipped` como `forbidden`, sem mudar.
#
#   POST .../crm/cards/restore { ids: [...], force: false }
#   => { payload: { restored: [...], skipped: [{ id:, error:, open_card_id: }] } }
class Api::V1::Accounts::Crm::Cards::RestoresController < Api::V1::Accounts::Crm::BaseController
  def create
    authorize ::Crm::Card, :index?

    result = ::Crm::Cards::BulkRestorer.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user,
      ids: params[:ids],
      force: ActiveModel::Type::Boolean.new.cast(params[:force]) || false
    ).perform

    render json: { payload: result }
  end
end
