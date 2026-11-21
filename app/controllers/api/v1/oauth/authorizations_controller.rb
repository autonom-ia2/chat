class Api::V1::Oauth::AuthorizationsController < Doorkeeper::AuthorizationsController
  # A client that identifies itself by a document URL (CIMD) is created or refreshed before Doorkeeper looks it up.
  before_action :sync_metadata_document_client

  def create
    # The token only works for this account, and only administrators may connect apps (#3089).
    # The account must be active too: /mcp refuses suspended accounts, so a token for one would never work.
    unless current_user.account_users.administrator.joins(:account).merge(Account.active).exists?(account_id: params[:account_id])
      return render_could_not_create_error(I18n.t('oauth.authorizations.invalid_account'))
    end

    super
  end

  private

  def sync_metadata_document_client
    Oauth::ClientMetadataDocument.sync(params[:client_id]) if Oauth::ClientMetadataDocument.url?(params[:client_id])
  end
end
