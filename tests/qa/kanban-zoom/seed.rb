# Local, synthetic fixtures for the Kanban zoom browser regression.
# Run only after loading the schema into a dedicated disposable QA database.
require 'json'
require 'securerandom'

connection = ActiveRecord::Base.connection_db_config.configuration_hash
unless !Rails.env.production? && %w[127.0.0.1 localhost].include?(connection[:host]) && connection[:database].start_with?('chat2you_839_')
  abort 'Refusing to seed anything except the dedicated local chat2you_839_* QA database'
end

fixture_path = Rails.root.join('.codex/839/fixture.json')
abort 'Fixtures already created; reuse the existing QA database' if fixture_path.exist?

ConfigLoader.new.process
GlobalConfig.clear_cache
account = Account.create!(name: 'Hub2You · QA', locale: 'pt_BR')
other_account = Account.create!(name: 'Outra conta · QA', locale: 'pt_BR')
password = "Zoom839!#{SecureRandom.hex(12)}"
user = User.new(name: 'Operador QA', email: 'kanban839@example.test', password: password)
user.skip_confirmation!
user.save!
[account, other_account].each do |current|
  AccountUser.create!(account: current, user: user, role: :administrator)
end

pipeline = account.crm_pipelines.create!(name: 'Email Comercial', created_by: user, is_default: true)
other_pipeline = account.crm_pipelines.create!(name: 'Outro funil', created_by: user)
names = ['Novo', 'Em atendimento', 'Proposta', 'Fechamento', 'Perdido']
colors = ['#2563eb', '#0891b2', '#ca8a04', '#16a34a', '#dc2626']
stages = names.each_with_index.map do |name, index|
  pipeline.stages.create!(account: account, name: name, color: colors[index], position: index)
end
other_pipeline.stages.create!(account: account, name: 'Entrada', color: colors.first, position: 0)
secondary = other_account.crm_pipelines.create!(name: 'Funil da outra conta', created_by: user, is_default: true)
secondary.stages.create!(account: other_account, name: 'Entrada', color: colors.first, position: 0)
companies = ['Aurora Seguros', 'Horizonte Digital', 'Norte Comercial', 'Atlas Consultoria', 'Maré Soluções'].map do |name|
  Company.create!(account: account, name: name)
end
contacts = companies.each_with_index.map do |company, index|
  account.contacts.create!(name: "Pessoa de teste #{index + 1}", email: "pessoa#{index + 1}@example.test", company: company)
end
counts = [28, 9, 0, 3, 2]
scores = [13, 8, 5, 27, 50]
ids = []
stages.each_with_index do |stage, stage_index|
  counts[stage_index].times do |index|
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, contact: contacts[index % contacts.size],
      title: "Oportunidade de teste #{stage_index + 1}-#{index + 1}",
      value_cents: stage_index == 3 ? 17_000_000 : 0,
      score: scores[index % scores.size],
      last_activity_at: Time.current - index.days,
      owner: index.odd? ? user : nil
    )
    ids << card.id
  end
end
standalone = account.crm_cards.create!(
  pipeline: pipeline, stage: stages.last,
  title: 'Oportunidade sem contato com título muito longo para validar o truncamento e a leitura em todas as escalas'
)
fixture = {
  email: user.email, password: password, user_id: user.id, account_id: account.id,
  other_account_id: other_account.id, pipeline_id: pipeline.id, other_pipeline_id: other_pipeline.id,
  stage_ids: stages.map(&:id), card_ids: ids, standalone_id: standalone.id
}
File.write(fixture_path, JSON.pretty_generate(fixture))
File.chmod(0o600, fixture_path)
puts "Synthetic QA fixtures ready: #{account.crm_cards.count} cards, #{stages.size} stages, two accounts. Credentials stored locally, not displayed."
