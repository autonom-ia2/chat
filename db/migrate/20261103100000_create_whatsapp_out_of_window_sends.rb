# Registro de cada mensagem automática enviada fora da janela de 24 h por modelo (#1585, decisão do Rodrigo em
# 15/10/2026: "Tabela própria"). Append-only: uma linha por mensagem, sem updated_at; o que vai nela é o
# `envio_fora_da_janela` que o `Whatsapp::Templates::EnvioForaDaJanela.enviar` devolve (tipo, caminho, escolha, modelo,
# categoria, origem e a autorização vigente). Gravado por `EnvioForaDaJanela.registrar_envio`.
#
# Registro ligado a dinheiro (Rodrigo, 15/10/2026): "Sim, trava no banco" e "Precisa guardar porque o cliente pode entrar
# na justiça tempos depois". Por isso:
# - sem chave estrangeira: conta, caixa, mensagem, follow-up e autorização são bigint simples, com índice. Apagar
#   qualquer uma delas no Chatwoot não apaga nem altera a linha (o id fica, mesmo sem a linha de origem);
# - o próprio Postgres recusa UPDATE, DELETE (por linha) e TRUNCATE. Corrigir uma linha no futuro exige uma migration que
#   desligue o gatilho, corrija e religue.
# Tabela nova, sem FK: nenhuma trava em tabela do Chatwoot. O índice único de message_id dá a idempotência.
# O gatilho vai para o schema.rb pelo dumper do hairtrigger (bloco `execute`), e o `db:schema:load` dos testes o recria.
class CreateWhatsappOutOfWindowSends < ActiveRecord::Migration[7.2]
  FUNCAO = 'whatsapp_out_of_window_sends_append_only'.freeze

  def up
    criar_tabela
    travar_no_banco
  end

  def down
    execute <<~SQL.squish
      DROP TRIGGER IF EXISTS #{FUNCAO}_truncate ON whatsapp_out_of_window_sends;
      DROP TRIGGER IF EXISTS #{FUNCAO}_row ON whatsapp_out_of_window_sends;
      DROP FUNCTION IF EXISTS #{FUNCAO}();
    SQL
    drop_table :whatsapp_out_of_window_sends
  end

  private

  def criar_tabela
    create_table :whatsapp_out_of_window_sends do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :message_id, index: { unique: true }
      t.bigint :crm_follow_up_id, index: true
      t.bigint :whatsapp_template_consent_id, index: { name: 'idx_whatsapp_oow_sends_consent' }
      t.string :tipo, null: false
      t.string :caminho, null: false
      t.string :escolha
      t.string :template_name, null: false
      t.string :template_language, null: false
      t.string :categoria, null: false
      t.string :origem, null: false
      t.string :motivo
      t.datetime :created_at, null: false
      t.index %i[account_id created_at], name: 'idx_whatsapp_oow_sends_account_created'
      t.index %i[inbox_id tipo], name: 'idx_whatsapp_oow_sends_inbox_tipo'
    end
  end

  # Os nomes dos gatilhos começam pelo nome da função: o dumper do hairtrigger ordena por nome, e a função precisa vir
  # antes dos gatilhos no schema.rb.
  def travar_no_banco
    execute <<~SQL.squish
      CREATE FUNCTION #{FUNCAO}() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'whatsapp_out_of_window_sends: registro append-only, % recusado', TG_OP;
      END;
      $$;
      CREATE TRIGGER #{FUNCAO}_row BEFORE UPDATE OR DELETE ON whatsapp_out_of_window_sends
        FOR EACH ROW EXECUTE FUNCTION #{FUNCAO}();
      CREATE TRIGGER #{FUNCAO}_truncate BEFORE TRUNCATE ON whatsapp_out_of_window_sends
        FOR EACH STATEMENT EXECUTE FUNCTION #{FUNCAO}();
    SQL
  end
end
