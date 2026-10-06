## we had instances where after copy pasting the schedule block,
## the dev forgets to changes the schedule key,
## this would break some of the scheduled jobs with out explicit errors
require 'rails_helper'

RSpec.context 'with valid schedule.yml' do
  it 'does not have duplicates' do
    file = Rails.root.join('config/schedule.yml')
    schedule_keys = []
    invalid_line_starts = [' ', '#', "\n"]
    # couldn't figure out a proper solution with yaml.parse
    # so the rudementary solution is to read the file and parse it
    # check for duplicates in the array
    File.open(file).each do |f|
      f.each_line do |line|
        next if invalid_line_starts.include?(line[0])

        schedule_keys << line.split(':')[0]
      end
    end
    # ensure that no duplicates exist
    expect(schedule_keys.count).to eq(schedule_keys.uniq.count)
  end

  # O sidekiq-cron enfileira cada job com `set(queue:).perform_later(*args)`. Um método do job que sobrescreva o
  # ActiveJob por engano (ex.: um `enqueue` privado, #1073) só quebra nesse caminho, nunca no perform_now dos testes.
  it 'enqueues every ActiveJob entry the way sidekiq-cron does' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

    schedule.each_value do |entry|
      klass = entry['class'].constantize
      next unless klass < ActiveJob::Base

      expect { klass.set(queue: entry['queue']).perform_later(*Array(entry['args'])) }.not_to raise_error, entry['class']
    end
  end
end
