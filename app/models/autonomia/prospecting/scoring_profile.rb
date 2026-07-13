class Autonomia::Prospecting::ScoringProfile < ApplicationRecord
  self.table_name = 'autonomia_prospecting_scoring_profiles'

  DEFAULT_WEIGHTS = {
    'website' => 25,
    'phone' => 10,
    'rating' => 20,
    'reviews_count' => 15,
    'activity' => 10,
    'photos' => 10,
    'google_rank' => 5,
    'query_relevance' => 5
  }.freeze

  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :name, presence: true
  validate :weights_must_be_supported_numbers

  before_validation :normalize_weights

  def self.default_profile
    where(default: true).first_or_create!(
      name: 'Padrão',
      weights: DEFAULT_WEIGHTS,
      default: true
    )
  rescue ActiveRecord::RecordNotUnique
    where(default: true).first!
  end

  def weights_with_defaults
    DEFAULT_WEIGHTS.merge(weights.to_h.slice(*DEFAULT_WEIGHTS.keys))
  end

  private

  def normalize_weights
    self.weights = DEFAULT_WEIGHTS.keys.index_with do |key|
      value = weights.to_h[key].presence || DEFAULT_WEIGHTS[key]
      value.to_i
    end
  end

  def weights_must_be_supported_numbers
    weights_with_defaults.each do |key, value|
      next if value.to_i.between?(0, 100)

      errors.add(:weights, "#{key} must be between 0 and 100")
    end

    return unless weights_with_defaults.values.sum <= 0

    errors.add(:weights, 'must have at least one positive weight')
  end
end
