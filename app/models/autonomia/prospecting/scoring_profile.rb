# == Schema Information
#
# Table name: autonomia_prospecting_scoring_profiles
#
#  id            :bigint           not null, primary key
#  default       :boolean          default(FALSE), not null
#  name          :string           default("Padrão"), not null
#  weights       :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#  updated_by_id :bigint
#
# Indexes
#
#  idx_autonomia_prospecting_scoring_profiles_default             (default) UNIQUE WHERE ("default" = true)
#  index_autonomia_prospecting_scoring_profiles_on_created_by_id  (created_by_id)
#  index_autonomia_prospecting_scoring_profiles_on_updated_by_id  (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (updated_by_id => users.id) ON DELETE => nullify
#
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
  # Sem conta vinculada o perfil é global; com contas vinculadas, só aparece e só vale para elas (#681).
  has_many :scoring_profile_accounts, class_name: 'Autonomia::Prospecting::ScoringProfileAccount', inverse_of: :scoring_profile,
                                      dependent: :delete_all
  has_many :accounts, through: :scoring_profile_accounts

  scope :available_to, lambda { |account|
    links = Autonomia::Prospecting::ScoringProfileAccount
    where.not(id: links.select(:scoring_profile_id)).or(where(id: links.where(account_id: account&.id).select(:scoring_profile_id)))
  }

  validates :name, presence: true
  validate :weights_must_be_supported_numbers
  validate :default_profile_must_be_global

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

  def restricted?
    account_ids.any?
  end

  def available_to?(account)
    !restricted? || account_ids.include?(account&.id)
  end

  def weights_with_defaults
    DEFAULT_WEIGHTS.merge(weights.to_h.slice(*DEFAULT_WEIGHTS.keys))
  end

  private

  # O padrão vale para toda conta sem escolha e para quem perde acesso a um perfil restrito: tem de ser global.
  def default_profile_must_be_global
    return unless default? && restricted?

    errors.add(:base, I18n.t('autonomia.prospecting.errors.default_scoring_profile_restricted'))
  end

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
