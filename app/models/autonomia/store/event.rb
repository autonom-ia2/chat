# frozen_string_literal: true

class Autonomia::Store::Event < ApplicationRecord
  self.table_name = 'autonomia_store_events'
  validates :body_sha256, :payload, presence: true
  validates :state, inclusion: { in: %w[pending processed ignored] }
end
