# frozen_string_literal: true

class Autonomia::Store::BuyerClient
  def self.fetch!(record, client_class: Autonomia::Financial::StoreCheckoutClient, **)
    user = record.user
    raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403) unless user.is_a?(SuperAdmin)

    token = Autonomia::Sso::TokenStore.authorization_token_for(user)
    raise Autonomia::Financial::StoreClientError.new('UNAUTHORIZED', status: 401) if token.blank?

    subject = Autonomia::Financial::StoreIdentity.subject!(token)
    configuration = Autonomia::Financial::StoreConfiguration.new
    namespace = { 'installationId' => record.installation_id, 'productCatalogItemId' => record.product_catalog_item_id }
    unless subject == record.buyer_subject && configuration.namespace == namespace
      raise Autonomia::Financial::StoreClientError.new('FORBIDDEN', status: 403)
    end

    client_class.new(configuration: configuration, subject: subject, authorization_token: token, **)
  end
end
