# Jogada salva pela conta (#732; MODO-25, MODO-26, FILTRO-27, PLAT-17): os filtros da gaveta com um nome, no modo da
# busca em que foram salvos. Aparece na grade ao lado das jogadas prontas e vai na busca como preset_id "saved-<id>".
class Autonomia::Prospecting::SavedPreset < ApplicationRecord
  self.table_name = 'autonomia_prospecting_saved_presets'

  MAX_PER_ACCOUNT = 30
  NAME_MAX_LENGTH = 60
  PRESET_ID_PREFIX = 'saved-'.freeze
  SCORE_MODES = %w[gbp general].freeze

  belongs_to :account
  belongs_to :user, optional: true

  before_validation :normalize_name
  before_validation :normalize_filters

  validate :name_must_be_present_and_short
  validate :name_must_be_unique_in_account
  validate :score_mode_must_be_supported
  validate :filters_must_follow_the_drawer
  validate :account_must_have_room, on: :create

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # Cria dentro do lock da configuração da conta: duas pessoas salvando juntas não passam do limite.
  def self.create_in_account(account, attributes)
    Autonomia::Prospecting::Setting.for_account(account).with_lock do
      create(attributes.merge(account: account))
    end
  end

  # "saved-12" da conta; id pronto, número solto ou id de outra conta não acham nada.
  def self.find_by_preset_id(account, preset_id)
    value = preset_id.to_s
    return unless value.start_with?(PRESET_ID_PREFIX)

    id = Integer(value.delete_prefix(PRESET_ID_PREFIX), 10, exception: false)
    return if id.nil? || id <= 0

    find_by(account: account, id: id)
  end

  def preset_id
    "#{PRESET_ID_PREFIX}#{id}"
  end

  def as_payload
    as_json(only: [:id, :name, :score_mode, :filters, :created_at, :updated_at]).merge('preset_id' => preset_id)
  end

  private

  def normalize_name
    self.name = name.to_s.squish
  end

  def normalize_filters
    normalized = Autonomia::Prospecting::SavedPresetFilters.normalize(filters)
    @filters_invalid = normalized.nil?
    self.filters = normalized unless @filters_invalid
  end

  def name_must_be_present_and_short
    add_base_error(:name_blank) if name.blank?
    add_base_error(:name_too_long, max: NAME_MAX_LENGTH) if name.length > NAME_MAX_LENGTH
  end

  def name_must_be_unique_in_account
    return if name.blank? || account_id.blank?

    taken = self.class.where(account_id: account_id).where.not(id: id).exists?(['lower(name) = ?', name.downcase])
    add_base_error(:name_taken) if taken
  end

  def score_mode_must_be_supported
    add_base_error(:invalid_score_mode) unless SCORE_MODES.include?(score_mode)
  end

  def filters_must_follow_the_drawer
    return add_base_error(:invalid_filters) if @filters_invalid

    add_base_error(:empty_filters) if filters.blank?
  end

  def account_must_have_room
    return if account_id.blank?

    add_base_error(:limit, max: MAX_PER_ACCOUNT) if self.class.where(account_id: account_id).count >= MAX_PER_ACCOUNT
  end

  def add_base_error(key, **)
    errors.add(:base, I18n.t("autonomia.prospecting.saved_presets.errors.#{key}", **))
  end
end
