# frozen_string_literal: true

class Autonomia::Store::Projection
  def self.apply!(envelope)
    raise Autonomia::Financial::StoreClientError.new('INVALID_RESPONSE', status: 502) if envelope.fetch('accessVersion').length > 30

    data = envelope.fetch('data')
    resource = data.fetch('resourceRef')
    return unless resource['type'] == 'chatwoot.account' && resource['id'].match?(/\A[1-9]\d{0,15}\z/)

    scope = projection_scope(envelope)
    return unless Autonomia::Store::Activation.where(scope).exists?

    return unless Account.exists?(scope[:account_id])

    row = Autonomia::Store::Entitlement.create_or_find_by!(scope) do |record|
      record.payload = { 'effectiveAccess' => 'ended', 'grants' => [] }
    end
    update_projection!(row, envelope)
    row
  end

  def self.update_projection!(row, envelope)
    row.with_lock do
      incoming = Integer(envelope.fetch('accessVersion'), 10)
      return if incoming <= row.access_version.to_i

      row.update!(access_version: incoming, payload: envelope.fetch('data'))
    end
    Autonomia::Store::AgentInstance.sync_account!(row.account_id)
  end
  private_class_method :update_projection!

  def self.projection_scope(envelope)
    namespace = envelope.fetch('namespace')
    data = envelope.fetch('data')
    { account_id: data.fetch('resourceRef').fetch('id').to_i, installation_id: namespace.fetch('installationId'),
      product_catalog_item_id: namespace.fetch('productCatalogItemId'), service_catalog_item_id: data.fetch('serviceCatalogItemId') }
  end
  private_class_method :projection_scope
end
