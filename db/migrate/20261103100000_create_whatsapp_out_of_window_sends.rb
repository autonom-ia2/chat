# Registro de cada mensagem automática enviada fora da janela de 24 h por modelo (#1585, decisão do Rodrigo em
# 15/10/2026: "Tabela própria"). Append-only: uma linha por mensagem, sem updated_at; o que vai nela é o
# `envio_fora_da_janela` que o `Whatsapp::Templates::EnvioForaDaJanela.enviar` devolve (tipo, caminho, escolha, modelo,
# categoria, origem e a autorização vigente). Gravado por `EnvioForaDaJanela.registrar_envio`.
#
# Conta e caixa apagadas levam o registro; mensagem, follow-up e autorização apagados só soltam a referência.
# Tabela nova: os índices nascem dentro do create_table, sem concurrently. O índice único de message_id dá a
# idempotência (a mesma mensagem não grava duas vezes) e sustenta o nullify quando a mensagem é apagada.
#
# As chaves estrangeiras pedem trava SHARE ROW EXCLUSIVE, rápida, em cada tabela referenciada (`messages`, `inboxes`,
# `accounts`, `crm_follow_ups`, `whatsapp_template_consents`): com uma transação longa na frente, desiste em 5 s em vez
# de enfileirar a escrita de mensagens atrás dela (rodar de novo).
class CreateWhatsappOutOfWindowSends < ActiveRecord::Migration[7.2]
  def change
    reversible { |direcao| direcao.up { execute "SET LOCAL lock_timeout = '5s'" } }
    create_table :whatsapp_out_of_window_sends do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :message, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.references :crm_follow_up, foreign_key: { on_delete: :nullify }, index: true
      t.references :whatsapp_template_consent, foreign_key: { on_delete: :nullify }, index: { name: 'idx_whatsapp_oow_sends_consent' }
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
end
