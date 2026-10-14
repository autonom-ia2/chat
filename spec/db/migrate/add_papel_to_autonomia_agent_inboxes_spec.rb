require 'rails_helper'
require Rails.root.join('db/migrate/20261027100000_add_papel_to_autonomia_agent_inboxes.rb')

# #1433 F1a — o papel do agente na caixa (porta|area). Tabela do fork; sai e volta limpa.
RSpec.describe AddPapelToAutonomiaAgentInboxes do
  let(:connection) { ActiveRecord::Base.connection }
  let(:tabela) { :autonomia_agent_inboxes }
  let(:migration) { described_class.new }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { Autonomia::Agents::Agent.create!(account: account, name: 'Porta', agent_type: 'custom') }
  let(:outro_agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'custom') }
  let(:bot) { AgentBot.create!(account: account, name: 'Espelho') }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  def dump_schema
    io = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    io.string
  end

  # Roda como o Migrator roda: numa transação. Aqui, num savepoint desfeito no fim.
  def numa_transacao_desfeita
    connection.transaction(requires_new: true) do
      yield
      raise ActiveRecord::Rollback
    end
  end

  def vinculo!(inbox:, agent:, bot:, deleted_at: nil)
    connection.select_value(<<~SQL.squish)
      INSERT INTO autonomia_agent_inboxes (autonomia_agent_id, inbox_id, account_id, agent_bot_id, deleted_at, created_at, updated_at)
      VALUES (#{agent.id}, #{inbox.id}, #{inbox.account_id}, #{bot.id}, #{deleted_at ? connection.quote(deleted_at) : 'NULL'}, now(), now())
      RETURNING id
    SQL
  end

  it 'down e up devolvem o mesmo schema' do
    antes = dump_schema

    numa_transacao_desfeita do
      migration.migrate(:down)
      expect(connection.column_exists?(tabela, :papel)).to be(false)
      expect(connection.index_name_exists?(tabela, described_class::INDICE_ANTIGO)).to be(true)

      migration.migrate(:up)
      expect(dump_schema).to eq(antes)
    end
  end

  it 'up marca todo vínculo existente como porta e troca o índice único da caixa pelo parcial da porta' do
    numa_transacao_desfeita do
      migration.migrate(:down)
      ativo = vinculo!(inbox: inbox, agent: agent, bot: bot)
      apagado = vinculo!(inbox: inbox, agent: outro_agente, bot: bot, deleted_at: 1.day.ago)

      migration.migrate(:up)

      papeis = connection.select_rows("SELECT id, papel FROM autonomia_agent_inboxes WHERE id IN (#{ativo}, #{apagado})").to_h
      expect(papeis.values).to eq(%w[porta porta])
      expect(connection.index_name_exists?(tabela, described_class::INDICE_ANTIGO)).to be(false)
      expect(connection.indexes(tabela).find { |i| i.name == described_class::INDICE_PORTA })
        .to have_attributes(unique: true, columns: ['inbox_id'], where: "(((papel)::text = 'porta'::text) AND (deleted_at IS NULL))")
      expect(connection.indexes(tabela).find { |i| i.name == described_class::INDICE_PAR })
        .to have_attributes(unique: true, columns: %w[inbox_id autonomia_agent_id], where: '(deleted_at IS NULL)')
    end
  end

  it 'up falha com mensagem clara, sem mudar nada, quando a caixa tem dois vínculos ativos' do
    numa_transacao_desfeita do
      migration.migrate(:down)
      connection.remove_index(tabela, name: described_class::INDICE_ANTIGO)
      vinculo!(inbox: inbox, agent: agent, bot: bot)
      vinculo!(inbox: inbox, agent: outro_agente, bot: bot)

      expect do
        connection.transaction(requires_new: true) { migration.migrate(:up) }
      end.to raise_error(described_class::VinculoDuplicado, /caixa.*#{inbox.id}/)
      expect(connection.column_exists?(tabela, :papel)).to be(false)
    end
  end

  it 'down recusa com mensagem clara quando já existe vínculo de área ativo' do
    numa_transacao_desfeita do
      porta = vinculo!(inbox: inbox, agent: agent, bot: bot)
      connection.execute(<<~SQL.squish)
        INSERT INTO autonomia_agent_inboxes (autonomia_agent_id, inbox_id, account_id, agent_bot_id, papel, created_at, updated_at)
        VALUES (#{outro_agente.id}, #{inbox.id}, #{inbox.account_id}, #{bot.id}, 'area', now(), now())
      SQL

      expect do
        connection.transaction(requires_new: true) { migration.migrate(:down) }
      end.to raise_error(described_class::AreaAtiva, /área/)
      expect(connection.select_value("SELECT papel FROM autonomia_agent_inboxes WHERE id = #{porta}")).to eq('porta')
    end
  end
end
