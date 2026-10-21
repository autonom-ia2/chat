require 'rails_helper'

RSpec.describe MigrationsSeguras::Dados do
  def motivos(codigo)
    described_class.new(codigo).motivos
  end

  it 'não marca migration só de schema, nem o require do topo nem o Rails.logger' do
    codigo = <<~RUBY
      require Rails.root.join('lib/feature_flag_rollout')

      class AddApelido < ActiveRecord::Migration[7.2]
        def up
          add_column :contacts, :apelido, :string
          Rails.logger.info('apelido')
        end

        def down
          raise ActiveRecord::IrreversibleMigration
        end
      end
    RUBY

    expect(motivos(codigo)).to be_empty
  end

  it 'marca model, update_all, connection.execute e SQL bruto' do
    codigo = <<~RUBY
      class Preenche < ActiveRecord::Migration[7.2]
        def up
          Contact.where(apelido: nil).update_all(apelido: '')
          connection.execute('UPDATE accounts SET locale = 0')
          reversible { |dir| dir.up { FeatureFlagRollout.padrao!('x', true) } }
        end
      end
    RUBY

    expect(motivos(codigo)).to contain_exactly('chama Contact', 'update_all (SQL ou linhas)', 'execute (SQL ou linhas)',
                                               'chama FeatureFlagRollout')
  end

  it 'lê o arquivo da migration' do
    arquivo = Rails.root.join('db/migrate/20261104100000_protect_whatsapp_template_consents.rb')

    expect(described_class.motivos(arquivo)).to include('execute (SQL ou linhas)')
  end
end
