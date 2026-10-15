# Autorização do dono para o sistema criar modelos da Meta (#1586): registro ligado a dinheiro. Decisões do Rodrigo em
# 15/10/2026: "Sim, trava no banco" e "Precisa guardar porque o cliente pode entrar na justiça tempos depois".
# - Tira as chaves estrangeiras de conta (cascade) e de usuário (nullify): apagar a conta ou o usuário no Chatwoot não
#   apaga nem altera a linha. As colunas e os índices ficam.
# - `user_name`: cópia do nome de quem mudou, para o registro não perder o "quem" se o usuário for apagado. As linhas
#   existentes recebem o nome atual ANTES do gatilho existir (depois dele, nenhum UPDATE passa).
# - O próprio Postgres recusa UPDATE, DELETE (por linha) e TRUNCATE. A trava é contra comando comum (do app ou de psql):
#   o dono da tabela ou um superusuário ainda conseguem `ALTER TABLE ... DISABLE TRIGGER`,
#   `SET session_replication_role = replica`, `DROP TRIGGER` ou `DROP TABLE`. Correção legítima (aceite gravado errado,
#   pedido de LGPD) = migration revisada que desliga o gatilho, corrige e religa.
# - Linha gravada pelo código antigo durante o deploy (entre esta migration e a troca do app) fica com `user_name` NULL;
#   a tela cai no nome atual do usuário. Risco aceito pelo Rodrigo em 15/10/2026.
#
# Tirar a FK pede trava rápida em `accounts` e `users` (somem os gatilhos internos da FK lá): com uma transação longa na
# frente, desiste em 5 s em vez de enfileirar a escrita nessas tabelas atrás dela (rodar de novo).
# O gatilho vai para o schema.rb pelo dumper do hairtrigger (bloco `execute`), e o `db:schema:load` dos testes o recria.
class ProtectWhatsappTemplateConsents < ActiveRecord::Migration[7.2]
  FUNCAO = 'whatsapp_template_consents_append_only'.freeze

  def up
    execute "SET LOCAL lock_timeout = '5s'"
    remove_foreign_key :whatsapp_template_consents, :accounts, if_exists: true
    remove_foreign_key :whatsapp_template_consents, :users, if_exists: true
    add_column :whatsapp_template_consents, :user_name, :string
    execute <<~SQL.squish
      UPDATE whatsapp_template_consents SET user_name = users.name
      FROM users WHERE users.id = whatsapp_template_consents.user_id
    SQL

    # Os nomes dos gatilhos começam pelo nome da função: o dumper do hairtrigger ordena por nome, e a função precisa vir
    # antes dos gatilhos no schema.rb.
    execute <<~SQL.squish
      CREATE FUNCTION #{FUNCAO}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'whatsapp_template_consents: registro append-only, % recusado', TG_OP;
      END;
      $$;
      CREATE TRIGGER #{FUNCAO}_row BEFORE UPDATE OR DELETE ON whatsapp_template_consents
        FOR EACH ROW EXECUTE FUNCTION #{FUNCAO}();
      CREATE TRIGGER #{FUNCAO}_truncate BEFORE TRUNCATE ON whatsapp_template_consents
        FOR EACH STATEMENT EXECUTE FUNCTION #{FUNCAO}();
    SQL
  end

  # Volta só com a tabela vazia: com linha gravada, tirar `user_name` perderia o "quem". Mesmo vazia, a volta não recria
  # as chaves estrangeiras: cascade apagaria registro guardado (Rodrigo, 15/10/2026). O `up` tira as FKs só se existirem.
  def down
    if select_value('SELECT EXISTS (SELECT 1 FROM whatsapp_template_consents)')
      raise ActiveRecord::IrreversibleMigration, 'whatsapp_template_consents tem registros guardados; a volta perderia user_name'
    end

    execute <<~SQL.squish
      DROP TRIGGER IF EXISTS #{FUNCAO}_truncate ON whatsapp_template_consents;
      DROP TRIGGER IF EXISTS #{FUNCAO}_row ON whatsapp_template_consents;
      DROP FUNCTION IF EXISTS #{FUNCAO}();
    SQL
    remove_column :whatsapp_template_consents, :user_name
  end
end
