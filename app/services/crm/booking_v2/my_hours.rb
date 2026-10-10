# "Meus horários" (#1195, J8-A11) de UMA pessoa: o que ela vê e o que pode gravar.
#
# Limites = o que as páginas novas em que ela atende permitem, juntas: os dias de alguma delas e da menor hora de
# início à maior de fim. Gravar fora disso é recusado (`OutsidePage`), e mesmo dentro o `Slots` ainda corta pela
# interseção com cada página, então a pessoa nunca amplia uma página. Sem página nenhuma não há o que ajustar
# (`NoPages`). Pausar e voltar sempre pode.
class Crm::BookingV2::MyHours
  class OutsidePage < StandardError; end
  class NoPages < StandardError; end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Sem horas próprias, mostra os limites das páginas como ponto de partida.
  def payload
    record = availability
    own = record.present? && record.custom_hours?
    limits = self.class.limits(pages)
    hours = own ? { weekdays: record.weekdays.sort, start_hour: record.start_hour, end_hour: record.end_hour } : page_hours(limits)
    { paused: record.present? && record.paused?, custom_hours: own, **hours, limits: limits,
      pages: pages.map { |page| { id: page.id, title: page.title } } }
  end

  # attrs: paused (bool) e/ou working_hours ({ start_hour, end_hour, weekdays }); `use_page_hours: true` volta a
  # seguir a página.
  def update!(attrs)
    record = availability || Crm::AgentAvailability.new(account: account, user: user)
    record.paused = ActiveModel::Type::Boolean.new.cast(attrs[:paused]) if attrs.key?(:paused)
    record.working_hours = new_hours(attrs) if attrs.key?(:working_hours) || attrs.key?(:use_page_hours)
    record.save!
    payload
  end

  def self.limits(pages)
    return if pages.empty?

    { weekdays: pages.flat_map(&:weekdays).uniq.sort, start_hour: pages.map(&:start_hour).min, end_hour: pages.map(&:end_hour).max }
  end

  private

  attr_reader :account, :user

  def page_hours(limits)
    return { weekdays: nil, start_hour: nil, end_hour: nil } if limits.nil?

    limits.slice(:weekdays, :start_hour, :end_hour)
  end

  def new_hours(attrs)
    return {} if ActiveModel::Type::Boolean.new.cast(attrs[:use_page_hours])

    hours = attrs[:working_hours].to_h.stringify_keys.slice(*Crm::AgentAvailability::HOUR_KEYS)
    hours['weekdays'] = Array(hours['weekdays']).map { |day| Integer(day.to_s, exception: false) || day }.uniq
    %w[start_hour end_hour].each { |key| hours[key] = Integer(hours[key].to_s, exception: false) || hours[key] }
    ensure_inside_pages!(hours)
    hours
  end

  def ensure_inside_pages!(hours)
    limits = self.class.limits(pages)
    raise NoPages if limits.nil?

    days_ok = (hours['weekdays'] - limits[:weekdays]).empty?
    hours_ok = [hours['start_hour'], hours['end_hour']].all?(Integer) &&
               hours['start_hour'] >= limits[:start_hour] && hours['end_hour'] <= limits[:end_hour]
    raise OutsidePage unless days_ok && hours_ok
  end

  def availability
    @availability ||= Crm::AgentAvailability.find_by(account_id: account.id, user_id: user.id)
  end

  # Páginas novas em que a pessoa atende: responsável fixo ou link individual ligado (no ar ou pausadas).
  def pages
    @pages ||= begin
      linked = account.crm_agent_booking_links.where(agent_id: user.id, enabled: true).select(:booking_profile_id)
      fixed = account.crm_agent_booking_profiles.new_pages.where(assignment_mode: :fixed, default_assignee_id: user.id)
      account.crm_agent_booking_profiles.new_pages.where(id: linked).or(fixed).order(:id).to_a
    end
  end
end
