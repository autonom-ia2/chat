# frozen_string_literal: true

class Autonomia::Store::Entitlement < ApplicationRecord
  self.table_name = 'autonomia_store_entitlements'
  belongs_to :account
  validates :installation_id, :product_catalog_item_id, :service_catalog_item_id, :payload, presence: true
end
