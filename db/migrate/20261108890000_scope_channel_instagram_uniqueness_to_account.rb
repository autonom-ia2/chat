# #2781: o mesmo Instagram ligado em mais de uma conta, como a Página do Facebook (índice único em page_id e
# account_id). Troca o índice único global de instagram_id por um único em (instagram_id, account_id).
#
# Sem travar as escritas: os índices entram e saem com concurrently, fora de transação. A unicidade fica protegida o
# tempo todo: primeiro nasce o índice novo, e o global só cai depois que o novo está válido. O índice novo começa por
# instagram_id, então continua servindo as buscas do webhook por instagram_id.
#
# Deploy que cai no meio: um CREATE INDEX CONCURRENTLY interrompido deixa o índice inválido com o mesmo nome. Rodar de
# novo apaga esse índice inválido e cria outra vez; o global nunca cai sem o novo válido.
#
# Rollback: `rails db:migrate:down VERSION=20261108890000`. Ele recria o único global. Se o mesmo Instagram já estiver
# ligado em duas contas, para antes de mexer em qualquer índice e avisa: é preciso desligar uma das caixas primeiro.
class ScopeChannelInstagramUniquenessToAccount < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  GLOBAL = 'index_channel_instagram_on_instagram_id'.freeze
  BY_ACCOUNT = 'index_channel_instagram_on_instagram_id_and_account_id'.freeze

  def up
    drop_if_invalid(BY_ACCOUNT)
    add_index :channel_instagram, [:instagram_id, :account_id],
              unique: true, name: BY_ACCOUNT, algorithm: :concurrently, if_not_exists: true
    raise "#{BY_ACCOUNT} ficou inválido; o índice global continua" unless index_valid?(BY_ACCOUNT)

    remove_index :channel_instagram, name: GLOBAL, algorithm: :concurrently, if_exists: true
  end

  def down
    raise 'o mesmo Instagram está em mais de uma conta; desligue uma das caixas antes do rollback' if shared_instagram?

    drop_if_invalid(GLOBAL)
    add_index :channel_instagram, :instagram_id, unique: true, name: GLOBAL, algorithm: :concurrently, if_not_exists: true
    raise "#{GLOBAL} ficou inválido; o índice por conta continua" unless index_valid?(GLOBAL)

    remove_index :channel_instagram, name: BY_ACCOUNT, algorithm: :concurrently, if_exists: true
  end

  private

  # true válido, false inválido (CREATE INDEX CONCURRENTLY interrompido), nil quando não existe.
  def index_state(name)
    value = select_value(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{quote(name)}
    SQL
    value.nil? ? nil : ActiveModel::Type::Boolean.new.cast(value)
  end

  def index_valid?(name)
    index_state(name) == true
  end

  def drop_if_invalid(name)
    remove_index :channel_instagram, name: name, algorithm: :concurrently if index_state(name) == false
  end

  def shared_instagram?
    select_value('SELECT 1 FROM channel_instagram GROUP BY instagram_id HAVING COUNT(*) > 1 LIMIT 1').present?
  end
end
