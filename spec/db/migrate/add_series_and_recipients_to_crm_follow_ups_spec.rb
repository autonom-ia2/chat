require 'rails_helper'
require Rails.root.join('db/migrate/20261028100000_create_crm_follow_up_series.rb')
require Rails.root.join('db/migrate/20261028100100_add_series_and_recipients_to_crm_follow_ups.rb')

# #1460/#1461/#1462 — as duas migrations dos lembretes. A de crm_follow_ups cria índices CONCURRENTLY, que não rodam
# dentro de transação: este spec roda fora da transação do teste e apaga o que criou no fim.
RSpec.describe AddSeriesAndRecipientsToCrmFollowUps do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:series_migration) { CreateCrmFollowUpSeries.new }
  let(:follow_ups_migration) { described_class.new }
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account, role: :administrator) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  after do
    connection.execute("DELETE FROM crm_follow_ups WHERE account_id = #{account.id}")
    connection.execute("DELETE FROM crm_cards WHERE account_id = #{account.id}")
    connection.execute("DELETE FROM crm_pipeline_stages WHERE account_id = #{account.id}")
    connection.execute("DELETE FROM crm_pipelines WHERE account_id = #{account.id}")
    AccountUser.where(account_id: account.id).delete_all
    User.where(id: user.id).delete_all
    Account.where(id: account.id).delete_all
  end

  def dump_schema
    io = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    io.string
  end

  def legacy_follow_up!
    pipeline = account.crm_pipelines.create!(name: 'Vendas', created_by: user, status: :active)
    stage = account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 0)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Plano anual')
    connection.select_value(<<~SQL.squish)
      INSERT INTO crm_follow_ups (account_id, card_id, title, due_at, timezone, metadata, created_at, updated_at)
      VALUES (#{account.id}, #{card.id}, 'Ligar', now(), 'UTC', '{}', now(), now()) RETURNING id
    SQL
  end

  it 'keeps every existing reminder (all with a card) valid under the new check, and comes back to the same schema' do
    antes = dump_schema
    follow_ups_migration.migrate(:down)
    series_migration.migrate(:down)
    expect(connection.column_exists?(:crm_follow_ups, :series_id)).to be(false)

    legado = legacy_follow_up!
    series_migration.migrate(:up)
    follow_ups_migration.migrate(:up)

    expect(dump_schema).to eq(antes)
    expect { connection.execute('ALTER TABLE crm_follow_ups VALIDATE CONSTRAINT crm_follow_ups_has_owner') }.not_to raise_error
    expect(connection.select_value("SELECT recipient_mode FROM crm_follow_ups WHERE id = #{legado}")).to eq(0)
  end

  it 'refuses a reminder without card, contact, company or creator' do
    expect do
      connection.execute(<<~SQL.squish)
        INSERT INTO crm_follow_ups (account_id, title, due_at, timezone, metadata, created_at, updated_at)
        VALUES (#{account.id}, 'Sem dono', now(), 'UTC', '{}', now(), now())
      SQL
    end.to raise_error(ActiveRecord::StatementInvalid, /crm_follow_ups_has_owner/)
  end
end
