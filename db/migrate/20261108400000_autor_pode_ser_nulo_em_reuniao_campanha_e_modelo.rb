# Exclusão do usuário (#2135): reunião, campanha e modelo do WhatsApp de quem foi excluído ficam com o autor nulo (a
# reunião passada mostra "Pessoa removida"). Criar continua exigindo autor, pela validação do modelo.
#
# DROP NOT NULL só mexe no catálogo (não lê nem reescreve a tabela), mas pede ACCESS EXCLUSIVE. Um ALTER por transação
# (sem a transação da migration), para a trava de uma tabela não ficar presa esperando a da outra. O lock_timeout de 5 s,
# com novas tentativas, vem do strong_migrations (config/initializers/strong_migrations.rb): atrás de transação longa o
# ALTER falha rápido e o deploy aborta limpo; rodar de novo pula o que já foi. A chave para users continua sem
# on_delete: quem anula o autor antes do DELETE é o Autonomia::ExclusaoDoUsuario.
class AutorPodeSerNuloEmReuniaoCampanhaEModelo < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TABELAS = %i[crm_meetings whatsapp_api_campaigns whatsapp_api_message_templates].freeze

  def up
    TABELAS.each { |tabela| change_column_null tabela, :created_by_id, true }
  end

  # Volta só nas tabelas sem linha sem autor: o Postgres recusa a tabela que tem, e as anteriores já voltaram (rodar de
  # novo é seguro, SET NOT NULL em coluna que já é NOT NULL não faz nada).
  def down
    safety_assured { TABELAS.each { |tabela| change_column_null tabela, :created_by_id, false } }
  end
end
