require 'rails_helper'
require Rails.root.join('db/migrate/20261024100000_create_campaign_free_texts.rb')

# #1335 — as duas tabelas do fork da conversa aberta entram e saem limpas, sem tocar nas tabelas do Chatwoot.
RSpec.describe CreateCampaignFreeTexts do
  let(:connection) { ActiveRecord::Base.connection }
  let(:tabelas) { %w[campaign_free_texts campaign_free_text_deliveries] }
  let(:colunas_do_chatwoot) { %w[campaigns campaign_recipients].index_with { |tabela| connection.columns(tabela).map(&:name) } }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  it 'down apaga as duas tabelas e up cria de novo, com os índices únicos' do
    antes = colunas_do_chatwoot

    described_class.new.down
    expect(tabelas.map { |tabela| connection.table_exists?(tabela) }).to eq([false, false])

    described_class.new.up
    expect(tabelas.map { |tabela| connection.table_exists?(tabela) }).to eq([true, true])
    expect(connection.index_exists?(:campaign_free_texts, :campaign_id, unique: true)).to be(true)
    expect(connection.index_exists?(:campaign_free_text_deliveries, :campaign_recipient_id, unique: true)).to be(true)
    expect(connection.index_exists?(:campaign_free_text_deliveries, [:inbox_id, :source_id], unique: true)).to be(true)
    expect(colunas_do_chatwoot).to eq(antes)
  end
end
