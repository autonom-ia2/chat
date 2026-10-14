# #1460/#1461/#1462 — cria um lembrete pelo painel: de uma vez só (como antes) ou que repete (uma série e a primeira
# vez). Com ou sem card: sem card, pode ser de um cliente (contact_id) ou de uma empresa (company_id, ficha do
# Relacionamento). Quem recebe vem do RecipientParams. A repetição é só para lembrete da equipe (fase 1).
class Crm::FollowUps::Creator
  RECURRENCE_KEYS = %i[frequency weekdays weekdays_only ends_mode ends_on occurrences_count].freeze

  def initialize(account:, user:, card:, conversation:, attributes:)
    @account = account
    @user = user
    @card = card
    @conversation = conversation
    @attributes = attributes
  end

  def perform
    attributes = base_attributes
    return @account.crm_follow_ups.create!(attributes) if recurrence.blank?

    create_series(attributes)
  end

  def self.recurrence_attributes(raw)
    {
      frequency: raw[:frequency], weekdays: Array(raw[:weekdays]).compact_blank.map(&:to_i),
      weekdays_only: ActiveModel::Type::Boolean.new.cast(raw[:weekdays_only]) || false,
      ends_mode: raw[:ends_mode].presence || 'never', ends_on: raw[:ends_on].presence,
      occurrences_count: raw[:occurrences_count].presence
    }
  end

  private

  def base_attributes
    resolved = Crm::FollowUps::ParamsResolver.new(
      account: @account, user: @user, card: @card, conversation: @conversation, attributes: @attributes
    ).perform
    recipients = Crm::FollowUps::RecipientParams.new(account: @account, card: @card, attributes: @attributes, user: @user).perform
    resolved.merge(recipients).merge(standalone_links).merge(card: @card, created_by: @user)
  end

  # Sem card: o cliente e a empresa escolhidos (da própria conta). Com card, valem os do card.
  def standalone_links
    return {} if @card.present?

    links = {}
    links[:contact_id] = @account.contacts.find(@attributes[:contact_id]).id if @attributes[:contact_id].present?
    links[:company_id] = @account.companies.find(@attributes[:company_id]).id if @attributes[:company_id].present?
    links
  end

  def recurrence
    @recurrence ||= begin
      raw = @attributes[:recurrence].to_h.with_indifferent_access.slice(*RECURRENCE_KEYS)
      raw[:frequency].present? && raw[:frequency] != 'none' ? raw : nil
    end
  end

  def create_series(attributes)
    series = @account.crm_follow_up_series.new(series_attributes(attributes))
    series.errors.add(:automation_mode, :inclusion) unless attributes[:automation_mode].to_s == 'reminder_only'
    raise ActiveRecord::RecordInvalid, series if series.errors.any?

    series.transaction do
      series.save!
      first = Crm::FollowUps::SeriesMaterializer.new(series).perform
      if first.nil?
        series.errors.add(:ends_on, 'leaves no date to remind')
        raise ActiveRecord::RecordInvalid, series
      end
      first
    end
  end

  def series_attributes(attributes)
    attributes.slice(:contact_id, :company_id, :conversation, :title, :description, :timezone, :recipient_user_ids,
                     :recipient_team_id)
              .merge(card: @card, created_by: @user, starts_at: attributes[:due_at],
                     recipient_mode: attributes[:recipient_mode] || 'legacy')
              .merge(self.class.recurrence_attributes(recurrence))
              .compact
  end
end
