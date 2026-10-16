require 'rails_helper'
require Rails.root.join('db/migrate/20261103100000_create_whatsapp_out_of_window_sends.rb')

# A migration do registro de envios fora da janela (#1585, Rodrigo 15/10/2026: "trava no banco", "precisa guardar"). Prova
# que a volta nunca apaga a tabela com registro dentro e que, vazia, vai e volta para o mesmo schema, com os gatilhos.
RSpec.describe CreateWhatsappOutOfWindowSends do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }
  let(:inbox) { create(:inbox) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
    WhatsappOutOfWindowSend.reset_column_information
  end

  def dump_schema
    io = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    io.string
  end

  def gatilhos
    connection.select_values(<<~SQL.squish)
      SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid = 'whatsapp_out_of_window_sends'::regclass ORDER BY tgname
    SQL
  end

  it 'com registro guardado, a volta recusa e não apaga a tabela' do
    linha = WhatsappOutOfWindowSend.create!(account: inbox.account, inbox: inbox, tipo: 'retorno', caminho: 'modelo', template_name: 'x',
                                            template_language: 'pt_BR', categoria: 'UTILITY', origem: 'sistema')

    expect { migration.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /registros guardados/)

    expect(WhatsappOutOfWindowSend.exists?(linha.id)).to be(true)
    expect(gatilhos).to eq(%w[whatsapp_out_of_window_sends_append_only_row whatsapp_out_of_window_sends_append_only_truncate])
  end

  it 'tabela vazia: volta e vai para o mesmo schema, com os gatilhos (por nome)' do
    antes = dump_schema
    migration.migrate(:down)
    expect(connection.table_exists?(:whatsapp_out_of_window_sends)).to be(false)

    migration.migrate(:up)

    expect(gatilhos).to eq(%w[whatsapp_out_of_window_sends_append_only_row whatsapp_out_of_window_sends_append_only_truncate])
    expect(connection.foreign_keys(:whatsapp_out_of_window_sends)).to be_empty
    expect(dump_schema).to eq(antes)
  end
end
