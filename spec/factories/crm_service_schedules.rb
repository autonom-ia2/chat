# frozen_string_literal: true

FactoryBot.define do
  # Blocks are built from +weekdays+ x +hours+ ("HH:MM" pairs) so specs read like a calendar.
  factory :crm_service_schedule, class: 'Crm::ServiceSchedule' do
    account
    owner { association :inbox, account: account }
    timezone { 'America/Sao_Paulo' }
    enabled { true }

    transient do
      weekdays { [1, 2, 3, 4, 5] }
      hours { [['09:00', '18:00']] }
    end

    blocks do
      to_minute = ->(clock) { clock.split(':').then { |hour, minute| (hour.to_i * 60) + minute.to_i } }
      weekdays.flat_map do |wday|
        hours.map { |from, to| { 'day_of_week' => wday, 'start_minute' => to_minute.call(from), 'end_minute' => to_minute.call(to) } }
      end
    end
  end
end
