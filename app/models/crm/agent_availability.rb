# "Meus horários" (#1195, J8-A11): os dias e horas em que UMA pessoa aceita reuniões das páginas novas, e a pausa
# da própria agenda. Não amplia nada: o `Crm::BookingV2::Slots` usa a interseção com o horário de cada página.
# `working_hours` vazio = segue a página. Mesmo formato do perfil (`start_hour`, `end_hour`, `weekdays` em
# Date#wday, 0 = domingo).
#
# Não reaproveita o calendário por agente do SLA (`Crm::ServiceSchedule` com dono User): aquele é configuração de
# administrador (policy admin/crm_admin) e entra na conta do prazo de SLA das conversas; deixar a pessoa mexer nele
# para marcar reuniões mudaria o SLA dela, e pausar a agenda desligaria o calendário de SLA.
class Crm::AgentAvailability < ApplicationRecord
  self.table_name = 'crm_agent_availabilities'

  HOUR_KEYS = %w[start_hour end_hour weekdays].freeze

  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
  validate :user_must_belong_to_account
  validate :working_hours_must_be_sane

  def custom_hours?
    working_hours.to_h.slice(*HOUR_KEYS).size == HOUR_KEYS.size
  end

  def start_hour
    working_hours.to_h['start_hour'].to_i
  end

  def end_hour
    working_hours.to_h['end_hour'].to_i
  end

  def weekdays
    Array(working_hours.to_h['weekdays']).map(&:to_i)
  end

  private

  def user_must_belong_to_account
    return if account.blank? || user_id.blank?
    return if account.account_users.exists?(user_id: user_id)

    errors.add(:user, 'must belong to the same account')
  end

  def working_hours_must_be_sane
    hours = working_hours
    return errors.add(:working_hours, 'must be an object') unless hours.is_a?(Hash)
    return if hours.blank?
    return errors.add(:working_hours, 'invalid working hours') unless custom_hours? && sane_hours?

    errors.add(:working_hours, 'invalid weekdays') unless sane_weekdays?
  end

  def sane_hours?
    raw = working_hours.values_at('start_hour', 'end_hour')
    raw.all?(Integer) && start_hour.between?(0, 23) && end_hour.between?(1, 24) && start_hour < end_hour
  end

  def sane_weekdays?
    list = working_hours['weekdays']
    list.is_a?(Array) && list.any? && list.all? { |day| day.is_a?(Integer) && day.between?(0, 6) } && list.uniq.size == list.size
  end
end
