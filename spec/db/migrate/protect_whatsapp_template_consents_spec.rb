require 'rails_helper'
require Rails.root.join('db/migrate/20261104100000_protect_whatsapp_template_consents.rb')

# A migration que trava no banco a autorização do dono (#1586, Rodrigo 15/10/2026). Prova que as linhas que já existem
# recebem o nome de quem mudou ANTES do gatilho (depois dele nenhum UPDATE passa), que a volta recusa com registro
# guardado, que a volta nunca recria FK e que o schema volta igual. Roda dentro da transação do teste: a migration é só DDL transacional.
RSpec.describe ProtectWhatsappTemplateConsents do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, name: 'Ana Antes') }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
    WhatsappTemplateConsent.reset_column_information
  end

  def dump_schema
    io = StringIO.new
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    io.string
  end

  def linha_antiga!(user_id)
    connection.select_value(<<~SQL.squish)
      INSERT INTO whatsapp_template_consents (account_id, user_id, marca, acao, versao_aviso, texto_aviso, precos, created_at)
      VALUES (#{account.id}, #{user_id || 'NULL'}, 'utility', 'ligou', 'v1', 'Aviso.', '{}', now()) RETURNING id
    SQL
  end

  def gatilhos
    connection.select_values(<<~SQL.squish)
      SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgrelid = 'whatsapp_template_consents'::regclass ORDER BY tgname
    SQL
  end

  it 'com linha guardada, a volta recusa e deixa tabela, user_name e os gatilhos (por nome) como estão' do
    linha = WhatsappTemplateConsent.create!(account: account, user: user, marca: 'utility', acao: 'ligou', versao_aviso: 'v1',
                                            texto_aviso: 'Aviso.')

    expect { migration.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /registros guardados/)

    expect(gatilhos).to eq(%w[whatsapp_template_consents_append_only_row whatsapp_template_consents_append_only_truncate])
    expect(WhatsappTemplateConsent.find(linha.id).user_name).to eq('Ana Antes')
  end

  it 'tabela vazia: volta sem recriar FK; na ida, preenche user_name das linhas antigas antes dos gatilhos (por nome)' do
    antes = dump_schema
    migration.migrate(:down)
    expect(gatilhos).to be_empty
    expect(connection.column_exists?(:whatsapp_template_consents, :user_name)).to be(false)
    expect(connection.foreign_keys(:whatsapp_template_consents)).to be_empty

    com_usuario = linha_antiga!(user.id)
    sem_usuario = linha_antiga!(nil)
    migration.migrate(:up)

    nomes = connection.select_rows("SELECT id, user_name FROM whatsapp_template_consents WHERE account_id = #{account.id} ORDER BY id")
    expect(nomes).to eq([[com_usuario, 'Ana Antes'], [sem_usuario, nil]])
    expect(gatilhos).to eq(%w[whatsapp_template_consents_append_only_row whatsapp_template_consents_append_only_truncate])
    expect(connection.foreign_keys(:whatsapp_template_consents)).to be_empty
    expect(dump_schema).to eq(antes)
  end
end
