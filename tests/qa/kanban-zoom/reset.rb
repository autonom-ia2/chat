# Restore only the synthetic fixture cards before another browser regression.
require 'json'

connection = ActiveRecord::Base.connection_db_config.configuration_hash
unless !Rails.env.production? && %w[127.0.0.1 localhost].include?(connection[:host]) && connection[:database].start_with?('chat2you_839_')
  abort 'Only the dedicated local chat2you_839_* QA database is permitted'
end
fixture = JSON.parse(File.read(Rails.root.join('.codex/839/fixture.json')))
account = Account.find(fixture.fetch('account_id'))
abort 'Not the synthetic QA account' unless account.name == 'Hub2You · QA'
offset = 0
[28, 9, 0, 3, 2].each_with_index do |count, index|
  ids = fixture.fetch('card_ids').slice(offset, count)
  account.crm_cards.where(id: ids).find_each do |card|
    card.update!(stage_id: fixture.fetch('stage_ids').fetch(index))
  end
  offset += count
end
puts 'Synthetic fixture stages restored; no unrelated records touched.'
