class Api::V1::Oauth::AuthorizationsController < Doorkeeper::AuthorizationsController
  # A client that identifies itself by a document URL (CIMD) is created or refreshed before Doorkeeper looks it up.
  before_action :sync_metadata_document_client

  def create
    # This account is the default one, and only administrators may connect apps (#3089).
    # The account must be active too: /mcp refuses suspended accounts, so a token for one would never work.
    unless current_user.account_users.administrator.joins(:account).merge(Account.active).exists?(account_id: params[:account_id])
      return render_could_not_create_error(I18n.t('oauth.authorizations.invalid_account'))
    end

    super
  end

  private

  # The consent screen says the connection covers every account the user administers (#3106), so the server marks the
  # grant that way. A value sent by the client is overwritten: it never decides how far the connection reaches.
  def pre_auth_params
    super.merge(all_accounts: true)
  end

  def sync_metadata_document_client
    Oauth::ClientMetadataDocument.sync(params[:client_id]) if Oauth::ClientMetadataDocument.url?(params[:client_id])
  end
end
